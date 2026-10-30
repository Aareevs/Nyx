import AppKit
import Foundation

struct SpotifyPlaylist: Identifiable, Equatable {
    let id: String
    let name: String
    let uri: String
    let owner: String
    let trackCount: Int
    let imageURL: URL?
}

struct SpotifyTrack: Identifiable, Equatable {
    var id: String { uri + "#\(position)" }
    let uri: String
    let name: String
    let artist: String
    let imageURL: URL?
    let position: Int
}

/// Reads the signed-in user's playlists and starts a song on the Spotify
/// app, through Spotify's web API.
@MainActor
final class SpotifyLibrary: ObservableObject {
    static let shared = SpotifyLibrary()

    @Published private(set) var playlists: [SpotifyPlaylist] = []
    @Published private(set) var tracks: [SpotifyTrack] = []
    @Published private(set) var loading = false
    @Published private(set) var message: String?

    private var loaded = false
    private let auth = SpotifyAuth.shared

    func loadPlaylists(force: Bool = false) async {
        guard auth.isConnected, !loading, force || !loaded else { return }
        loading = true
        message = nil
        defer { loading = false }
        do {
            var found: [SpotifyPlaylist] = []
            var next: String? = "https://api.spotify.com/v1/me/playlists?limit=50"
            while let url = next, found.count < 500 {
                let json = try await get(url)
                for item in json["items"] as? [[String: Any]] ?? [] {
                    guard let id = item["id"] as? String, let uri = item["uri"] as? String else { continue }
                    let total = ((item["tracks"] ?? item["items"]) as? [String: Any])?["total"] as? Int ?? 0
                    found.append(SpotifyPlaylist(
                        id: id, name: item["name"] as? String ?? "Playlist", uri: uri,
                        owner: (item["owner"] as? [String: Any])?["display_name"] as? String ?? "",
                        trackCount: total, imageURL: Self.image(item["images"])))
                }
                next = json["next"] as? String
            }
            playlists = found
            loaded = true
        } catch {
            message = Self.describe(error)
        }
    }

    func loadTracks(of playlist: SpotifyPlaylist) async {
        tracks = []
        loading = true
        message = nil
        defer { loading = false }
        do {
            var found: [SpotifyTrack] = []
            var next: String? = "https://api.spotify.com/v1/playlists/\(playlist.id)/items?limit=100"
            while let url = next, found.count < 1000 {
                let json = try await get(url)
                for item in json["items"] as? [[String: Any]] ?? [] {
                    guard let track = (item["track"] ?? item["item"]) as? [String: Any],
                          track["is_local"] as? Bool != true, track["type"] as? String != "episode",
                          let uri = track["uri"] as? String else { continue }
                    let artists = (track["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
                    found.append(SpotifyTrack(
                        uri: uri, name: track["name"] as? String ?? "", artist: artists.joined(separator: ", "),
                        imageURL: Self.image((track["album"] as? [String: Any])?["images"], small: true),
                        position: found.count))
                }
                next = json["next"] as? String
            }
            tracks = found
            if found.isEmpty { message = "No songs to show here" }
        } catch {
            message = Self.describe(error)
        }
    }

    /// Plays `track` inside `playlist`, so the rest of the playlist follows it.
    func play(_ track: SpotifyTrack?, in playlist: SpotifyPlaylist) async {
        message = nil
        var body: [String: Any] = ["context_uri": playlist.uri]
        if let track { body["offset"] = ["uri": track.uri] }
        do {
            try await startPlayback(body)
        } catch {
            message = Self.describe(error)
        }
    }

    private func startPlayback(_ body: [String: Any]) async throws {
        var device: String?
        for attempt in 0..<3 {
            var url = "https://api.spotify.com/v1/me/player/play"
            if let device { url += "?device_id=\(device)" }
            let status = try await send("PUT", url, body: body)
            switch status {
            case 200..<300: return
            case 403: throw SpotifyError.premiumRequired
            case 404:
                // Nothing is awake to play: wake a player that is already
                // known; failing that, start the app behind the current
                // window, and wait for it to appear.
                device = try await firstDevice()
                if device == nil, attempt == 0 { device = try await launchSpotify() }
                if device == nil { throw SpotifyError.noDevice }
            default: throw SpotifyError.network
            }
        }
        throw SpotifyError.noDevice
    }

    /// Starts Spotify without bringing it forward, then waits for it to
    /// register as a player.
    private func launchSpotify() async throws -> String? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        for _ in 0..<10 {
            try await Task.sleep(for: .seconds(1))
            if let device = try await firstDevice() { return device }
        }
        return nil
    }

    private func firstDevice() async throws -> String? {
        let json = try await get("https://api.spotify.com/v1/me/player/devices")
        let devices = json["devices"] as? [[String: Any]] ?? []
        return (devices.first { $0["is_active"] as? Bool == true } ?? devices.first)?["id"] as? String
    }

    // MARK: Requests

    private func get(_ url: String) async throws -> [String: Any] {
        let token = try await auth.accessToken()
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw status == 401 ? SpotifyError.rejected : SpotifyError.network }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func send(_ method: String, _ url: String, body: [String: Any]) async throws -> Int {
        let token = try await auth.accessToken()
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private static func image(_ value: Any?, small: Bool = false) -> URL? {
        let images = value as? [[String: Any]] ?? []
        let pick = small ? images.last : (images.count > 1 ? images[images.count - 2] : images.first)
        return (pick?["url"] as? String).flatMap(URL.init(string:))
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case SpotifyError.premiumRequired: return "Choosing songs needs Spotify Premium"
        case SpotifyError.noDevice: return "Open Spotify on this Mac, then try again"
        case SpotifyError.notConnected, SpotifyError.rejected: return "Spotify needs you to sign in again"
        default: return "Couldn't reach Spotify"
        }
    }
}
