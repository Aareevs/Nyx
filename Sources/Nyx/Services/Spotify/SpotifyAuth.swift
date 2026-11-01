import AppKit
import CryptoKit
import Foundation
import Network
import Security

/// Signs in to Spotify with the authorization-code flow and PKCE, so no
/// secret is shipped: the app only holds a public client id. The login page
/// opens in the browser and Spotify sends it back to a port on this Mac.
@MainActor
final class SpotifyAuth: ObservableObject {
    static let shared = SpotifyAuth()

    static let clientID = "96989a67bd41405fb9588a61e1ac9511"
    static let redirectPort: UInt16 = 8888
    static let redirectURI = "http://127.0.0.1:8888/callback"
    private static let scopes = "playlist-read-private playlist-read-collaborative user-modify-playback-state user-read-playback-state user-read-currently-playing"

    enum State: Equatable { case disconnected, connecting, connected, failed(String) }

    @Published private(set) var state: State = .disconnected

    private struct Tokens: Codable {
        var access: String
        var refresh: String
        var expires: Date
    }

    private var tokens: Tokens?
    private var listener: NWListener?
    private var verifier = ""
    private var oauthState = ""
    private var timeout: Task<Void, Never>?

    private init() {
        tokens = SpotifyLoginStore.read().flatMap { try? JSONDecoder().decode(Tokens.self, from: $0) }
        if tokens != nil { state = .connected }
    }

    var isConnected: Bool { tokens != nil }

    // MARK: Login

    func connect() {
        guard state != .connecting else { return }
        verifier = Self.randomString(64)
        oauthState = Self.randomString(16)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        guard startListener() else {
            state = .failed("Port \(Self.redirectPort) is busy")
            return
        }
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: Self.clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI), .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: oauthState),
        ]
        state = .connecting
        NSWorkspace.shared.open(components.url!)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled else { return }
            self?.finish(.failed("Login timed out"))
        }
    }

    func disconnect() {
        SpotifyLoginStore.delete()
        tokens = nil
        finish(.disconnected)
    }

    private func finish(_ result: State) {
        timeout?.cancel()
        listener?.cancel()
        listener = nil
        state = result
    }

    private func startListener() -> Bool {
        listener?.cancel()
        guard let port = NWEndpoint.Port(rawValue: Self.redirectPort),
              let listener = try? NWListener(using: .tcp, on: port) else { return false }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let page = "Nyx is connected to Spotify. You can close this tab."
                let body = "<html><body style=\"font-family:-apple-system;text-align:center;margin-top:20vh\"><h2>\(page)</h2></body></html>"
                let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
                Task { @MainActor in SpotifyAuth.shared.handle(request: request) }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
        return true
    }

    private func handle(request: String) {
        guard state == .connecting,
              let line = request.split(separator: "\r\n").first, line.hasPrefix("GET /callback"),
              let target = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://127.0.0.1" + target) else { return }
        let items = Dictionary(components.queryItems?.compactMap { item in item.value.map { (item.name, $0) } } ?? [],
                               uniquingKeysWith: { first, _ in first })
        guard items["state"] == oauthState else { return }
        guard let code = items["code"] else {
            finish(.failed(items["error"] ?? "Login was cancelled"))
            return
        }
        Task {
            do {
                let tokens = try await Self.request(["grant_type": "authorization_code", "code": code,
                                                     "redirect_uri": Self.redirectURI, "code_verifier": verifier],
                                                    keeping: nil)
                store(tokens)
                finish(.connected)
            } catch {
                finish(.failed("Spotify refused the login"))
            }
        }
    }

    // MARK: Tokens

    /// A token that is good for at least the next minute, refreshed when it is not.
    func accessToken() async throws -> String {
        guard let current = tokens else { throw SpotifyError.notConnected }
        if current.expires > Date().addingTimeInterval(60) { return current.access }
        do {
            let renewed = try await Self.request(["grant_type": "refresh_token", "refresh_token": current.refresh],
                                                 keeping: current.refresh)
            store(renewed)
            return renewed.access
        } catch {
            if case SpotifyError.rejected = error { disconnect() }
            throw error
        }
    }

    private func store(_ new: Tokens) {
        tokens = new
        if let data = try? JSONEncoder().encode(new) { SpotifyLoginStore.write(data) }
    }

    private static func request(_ form: [String: String], keeping refresh: String?) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = form
        body["client_id"] = clientID
        request.httpBody = Data(body.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value)"
        }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw (400..<500).contains(status) ? SpotifyError.rejected : SpotifyError.network }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = (json["refresh_token"] as? String) ?? refresh else { throw SpotifyError.network }
        let lifetime = (json["expires_in"] as? Double) ?? 3600
        return Tokens(access: access, refresh: refresh, expires: Date().addingTimeInterval(lifetime))
    }

    private static func randomString(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(Data(bytes).base64URL.prefix(length))
    }
}

enum SpotifyError: Error { case notConnected, rejected, network, noDevice, premiumRequired, notAllowed }

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The login sits in a file only this account can read, in the app's own
/// folder. The Keychain asked for the password again after every update,
/// since an app it does not recognise as the same one is asked about anew.
enum SpotifyLoginStore {
    private static var file: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("spotify-login.json")
    }

    static func read() -> Data? {
        file.flatMap { try? Data(contentsOf: $0) }
    }

    static func write(_ data: Data) {
        guard let file, PrivateFileStore.createDirectory(at: file.deletingLastPathComponent()) else { return }
        PrivateFileStore.write(data, to: file)
    }

    static func delete() {
        if let file { try? FileManager.default.removeItem(at: file) }
    }
}
