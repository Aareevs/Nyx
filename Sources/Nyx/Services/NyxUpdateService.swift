import Foundation
import AppKit

/// Looks for a newer Nyx on its GitHub releases page and points to the
/// download. It never installs anything itself: Nyx is not signed with an
/// Apple Developer ID, so a new copy still goes through "Open Anyway".
@MainActor
final class NyxUpdateService: ObservableObject {
    static let shared = NyxUpdateService()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    @Published private(set) var state: State = .idle

    private static let latestURL = URL(string: "https://api.github.com/repos/Aareevs/Nyx/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/Aareevs/Nyx/releases/latest")!

    /// Pure comparison, kept separate so it can be tested.
    nonisolated static func newer(_ remote: String, than local: String) -> Bool {
        guard let remote = VersionSupport.SemanticVersion(raw: remote),
              let local = VersionSupport.SemanticVersion(raw: local) else { return false }
        return remote > local
    }

    /// Run once a day at launch, only when the user turned automatic checks on.
    func checkAtLaunchIfWanted() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.updateCheckAuto) else { return }
        let last = defaults.double(forKey: DefaultsKey.updateLastCheck)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        check()
    }

    func check() {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: Self.latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Nyx/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        Task {
            let result: State
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    // 404 means no release has been published yet.
                    result = (response as? HTTPURLResponse)?.statusCode == 404 ? .upToDate : .failed
                    finish(result)
                    return
                }
                let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.releasesPage
                result = Self.newer(tag, than: AppInfo.version)
                    ? .available(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), url: page)
                    : .upToDate
            } catch {
                result = .failed
            }
            finish(result)
        }
    }

    private func finish(_ result: State) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: DefaultsKey.updateLastCheck)
        state = result
    }
}
