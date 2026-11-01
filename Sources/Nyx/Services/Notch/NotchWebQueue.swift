import AppKit

/// Upcoming songs for players that keep their queue to themselves. Spotify's
/// comes from the signed-in account's web service. For YouTube the playing
/// tab's address names the playlist, and the playlist's public page lists the
/// videos after the one that plays. Both wait for the online lookup setting.
enum NotchWebQueue {
    enum Source: Equatable {
        case spotify
        /// `scriptName` is the application's name in AppleScript, `usesName` is
        /// true for Safari, whose tabs call their title "name".
        case browser(scriptName: String, usesName: Bool)
    }

    enum Failure: Error, Equatable { case needsOnline, needsSpotifyLogin, needsBrowserScripting, noPlaylist, unavailable }

    /// A queue and whether a row of it can be played from the island.
    struct Loaded {
        let items: [NotchQueueItem]
        let canPlay: Bool
    }

    private static let browsers: [String: Source] = [
        "com.microsoft.edgemac": .browser(scriptName: "Microsoft Edge", usesName: false),
        "com.google.Chrome": .browser(scriptName: "Google Chrome", usesName: false),
        "com.brave.Browser": .browser(scriptName: "Brave Browser", usesName: false),
        "com.vivaldi.Vivaldi": .browser(scriptName: "Vivaldi", usesName: false),
        "company.thebrowser.Browser": .browser(scriptName: "Arc", usesName: false),
        "com.apple.Safari": .browser(scriptName: "Safari", usesName: true)
    ]

    static func source(forBundle identifier: String?) -> Source? {
        guard let identifier else { return nil }
        return identifier == "com.spotify.client" ? .spotify : browsers[identifier]
    }

    static func isOnlineEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchQueueOnline)
    }

    // MARK: Fetching

    @MainActor
    static func fetch(_ source: Source, playback: NotchPlayback) async -> Result<Loaded, Failure> {
        guard isOnlineEnabled() else { return .failure(.needsOnline) }
        switch source {
        case .spotify: return await spotify()
        case let .browser(name, usesName): return await youTube(app: name, usesName: usesName, title: playback.track.title ?? "")
        }
    }

    // MARK: Spotify

    @MainActor
    private static func spotify() async -> Result<Loaded, Failure> {
        guard SpotifyAuth.shared.isConnected, let token = try? await SpotifyAuth.shared.accessToken() else {
            return .failure(.needsSpotifyLogin)
        }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/queue")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failure(.unavailable) }
        // A login made before the queue permission existed answers 403.
        if status == 401 || status == 403 { return .failure(.needsSpotifyLogin) }
        guard status == 200, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.unavailable)
        }
        let rows = (object["queue"] as? [[String: Any]] ?? []).prefix(NotchQueueSupport.maximumItems)
        var drafts: [(id: String, title: String, artist: String, duration: Double, cover: URL?)] = []
        for row in rows {
            guard let id = row["id"] as? String, let title = row["name"] as? String, !title.isEmpty else { continue }
            let artist = (row["artists"] as? [[String: Any]])?.first?["name"] as? String
                ?? (row["show"] as? [String: Any])?["publisher"] as? String ?? ""
            let images = ((row["album"] as? [String: Any]) ?? (row["show"] as? [String: Any]))?["images"] as? [[String: Any]]
            drafts.append((id, title, artist, (row["duration_ms"] as? Double ?? 0) / 1000,
                           (images?.last?["url"] as? String).flatMap(URL.init(string:))))
        }
        let covers = await covers(for: drafts.prefix(12).map(\.cover))
        return .success(Loaded(items: drafts.enumerated().map { index, draft in
            NotchQueueItem(id: "\(index)-\(draft.id)", offset: index + 1, title: draft.title, artist: draft.artist,
                           duration: draft.duration, artwork: index < covers.count ? covers[index] : nil)
        }, canPlay: true))
    }

    /// Spotify has no jump to a queued song, so it skips ahead that many
    /// songs, which also keeps the playlist the song came from.
    @MainActor
    static func playSpotify(offset: Int) async -> Bool {
        guard offset >= 1, offset <= NotchQueueSupport.maximumItems,
              let token = try? await SpotifyAuth.shared.accessToken() else { return false }
        for _ in 0..<offset {
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/next")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 8
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode, (200...204).contains(status) else { return false }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return true
    }

    // MARK: YouTube

    private struct Entry {
        let id: String
        let title: String
        let artist: String
        let duration: Double
    }

    /// The playing tab's own playlist panel is the best source: it is what the
    /// person sees, private playlists included. It needs the browser's
    /// "Allow JavaScript from Apple Events" choice. Without it, the playlist's
    /// public page is the fallback, which cannot show a private one.
    @MainActor
    private static func youTube(app: String, usesName: Bool, title: String) async -> Result<Loaded, Failure> {
        let panel = await Task.detached { runInTab(app: app, usesName: usesName, title: title, javascript: panelScript) }.value
        switch panel {
        case let .value(json):
            let entries = panelEntries(json)
            guard let position = entries.firstIndex(where: \.selected) else { return .failure(.noPlaylist) }
            let upcoming = Array(entries[(position + 1)...].prefix(NotchQueueSupport.maximumItems))
            return .success(Loaded(items: await rows(upcoming.map { ($0.id, $0.title, $0.artist, $0.duration) }), canPlay: true))
        case .scriptingOff:
            if let loaded = await publicPlaylist(app: app, usesName: usesName, title: title) { return .success(loaded) }
            return .failure(.needsBrowserScripting)
        case .noTab, .failed:
            return .failure(.unavailable)
        }
    }

    private static let panelScript = "(function(){var n=document.querySelectorAll('ytd-playlist-panel-video-renderer');var r=[];for(var i=0;i<n.length;i++){var e=n[i];var a=e.querySelector('a#wc-endpoint');var u=a?new URL(a.href):null;var t=e.querySelector('#video-title');var b=e.querySelector('#byline');r.push({id:u?u.searchParams.get('v'):null,title:t?t.textContent.trim():'',by:b?b.textContent.trim():'',sel:e.hasAttribute('selected')});}return JSON.stringify(r);})()"

    private struct PanelEntry {
        let id: String
        let title: String
        let artist: String
        let duration: Double
        let selected: Bool
    }

    private static func panelEntries(_ json: String) -> [PanelEntry] {
        guard let rows = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? String, validVideo(id), let title = row["title"] as? String, !title.isEmpty else { return nil }
            return PanelEntry(id: id, title: title, artist: row["by"] as? String ?? "", duration: 0,
                              selected: row["sel"] as? Bool == true)
        }
    }

    private static func validVideo(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9_-]{6,20}$"#, options: .regularExpression) != nil
    }

    /// Plays a row of the playing tab's own playlist panel, so the tab moves on
    /// without a reload and keeps its playlist.
    @MainActor
    static func playYouTube(app: String, usesName: Bool, title: String, itemID: String) async -> Bool {
        let id = String(itemID.drop(while: { $0 != "-" }).dropFirst())
        guard validVideo(id) else { return false }
        let script = "(function(){var a=document.querySelectorAll('ytd-playlist-panel-video-renderer a#wc-endpoint');for(var i=0;i<a.length;i++){if(a[i].href.indexOf('v=\(id)')>0){a[i].click();return 'ok';}}return 'none';})()"
        let result = await Task.detached { runInTab(app: app, usesName: usesName, title: title, javascript: script) }.value
        if case .value("ok") = result { return true }
        return false
    }

    @MainActor
    private static func publicPlaylist(app: String, usesName: Bool, title: String) async -> Loaded? {
        let tab = await Task.detached { playingTab(app: app, usesName: usesName, title: title) }.value
        guard let tab, let parts = URLComponents(string: tab),
              let host = parts.host, host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        let query = Dictionary((parts.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
                               uniquingKeysWith: { first, _ in first })
        guard let list = query["list"], list.range(of: #"^[A-Za-z0-9_-]{2,80}$"#, options: .regularExpression) != nil,
              !list.hasPrefix("RD"),
              let page = await download("https://www.youtube.com/playlist?list=\(list)", maximumBytes: 6_000_000),
              let html = String(data: page, encoding: .utf8) ?? String(data: page, encoding: .isoLatin1) else { return nil }
        let entries = playlistEntries(in: html)
        guard let position = query["v"].flatMap({ id in entries.firstIndex { $0.id == id } })
            ?? query["index"].flatMap(Int.init).map({ $0 - 1 }), entries.indices.contains(position) else { return nil }
        let upcoming = Array(entries[(position + 1)...].prefix(NotchQueueSupport.maximumItems))
        return Loaded(items: await rows(upcoming.map { ($0.id, $0.title, $0.artist, $0.duration) }), canPlay: false)
    }

    /// Rows with their small covers fetched alongside.
    private static func rows(_ entries: [(id: String, title: String, artist: String, duration: Double)]) async -> [NotchQueueItem] {
        let covers = await covers(for: entries.prefix(12).map { URL(string: "https://i.ytimg.com/vi/\($0.id)/default.jpg") })
        return entries.enumerated().map { index, entry in
            NotchQueueItem(id: "\(index)-\(entry.id)", offset: index + 1, title: entry.title, artist: entry.artist,
                           duration: entry.duration, artwork: index < covers.count ? covers[index] : nil)
        }
    }

    private enum ScriptOutcome { case value(String), scriptingOff, noTab, failed }

    /// Runs JavaScript in the browser tab whose title is the song's.
    private static func runInTab(app: String, usesName: Bool, title: String, javascript: String) -> ScriptOutcome {
        let wanted = normalized(title)
        guard !wanted.isEmpty, !NSRunningApplication.runningApplications(withBundleIdentifier: bundle(of: app)).isEmpty else { return .noTab }
        func quoted(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let run = usesName ? "do JavaScript \"\(quoted(javascript))\" in t" : "execute t javascript \"\(quoted(javascript))\""
        let script = """
        tell application "\(app)"
            repeat with w in windows
                repeat with t in tabs of w
                    if (URL of t) contains "youtube.com" and (\(usesName ? "name" : "title") of t) contains "\(quoted(wanted))" then
                        return \(run)
                    end if
                end repeat
            end repeat
            return "__notab__"
        end tell
        """
        var error: NSDictionary?
        guard let output = NSAppleScript(source: script)?.executeAndReturnError(&error) else {
            let message = (error?[NSAppleScript.errorMessage] as? String ?? "").lowercased()
            return message.contains("javascript") ? .scriptingOff : .failed
        }
        guard let value = output.stringValue else { return .failed }
        return value == "__notab__" ? .noTab : .value(value)
    }

    /// The address of the tab whose title is the song's, asked of the browser.
    private static func playingTab(app: String, usesName: Bool, title: String) -> String? {
        let wanted = normalized(title)
        guard !wanted.isEmpty else { return nil }
        let script = """
        tell application "\(app)"
            set rows to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set rows to rows & (URL of t) & "\\t" & (\(usesName ? "name" : "title") of t) & "\\n"
                end repeat
            end repeat
            return rows
        end tell
        """
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundle(of: app)).isEmpty == false,
              let output = NSAppleScript(source: script)?.executeAndReturnError(nil).stringValue else { return nil }
        for row in output.split(separator: "\n") {
            let fields = row.split(separator: "\t", maxSplits: 1).map(String.init)
            guard fields.count == 2, fields[0].contains("youtube.com") else { continue }
            let tab = normalized(fields[1])
            if tab.contains(wanted) || wanted.contains(tab) { return fields[0] }
        }
        return nil
    }

    private static func bundle(of app: String) -> String {
        browsers.first { if case let .browser(name, _) = $0.value { return name == app } else { return false } }?.key ?? ""
    }

    /// A title without the browser's unread count or the site's name.
    private static func normalized(_ title: String) -> String {
        var text = title.lowercased()
        if let range = text.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) { text.removeSubrange(range) }
        for suffix in [" - youtube music", " - youtube"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func playlistEntries(in html: String) -> [Entry] {
        guard let start = html.range(of: "ytInitialData = ") else { return [] }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: ";</script>"),
              let object = try? JSONSerialization.jsonObject(with: Data(rest[..<end.lowerBound].utf8)) else { return [] }
        var entries: [Entry] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let renderer = dictionary["playlistVideoRenderer"] as? [String: Any],
                   let id = renderer["videoId"] as? String, let title = text(renderer["title"]), !title.isEmpty {
                    entries.append(Entry(id: id, title: title, artist: text(renderer["shortBylineText"]) ?? "",
                                         duration: Double(renderer["lengthSeconds"] as? String ?? "") ?? 0))
                } else if let lockup = dictionary["lockupViewModel"] as? [String: Any] {
                    // YouTube's newer playlist page lists each video as a lockup.
                    let metadata = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
                    let rows = ((metadata?["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any])?["metadataRows"] as? [[String: Any]]
                    let artist = ((rows?.first?["metadataParts"] as? [[String: Any]])?.first?["text"] as? [String: Any])?["content"] as? String
                    if lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO", let id = lockup["contentId"] as? String,
                       let title = (metadata?["title"] as? [String: Any])?["content"] as? String, !title.isEmpty {
                        entries.append(Entry(id: id, title: title, artist: artist ?? "", duration: 0))
                    }
                } else {
                    for child in dictionary.values { walk(child) }
                }
            } else if let array = value as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(object)
        return entries
    }

    private static func text(_ value: Any?) -> String? {
        let object = value as? [String: Any]
        return (object?["simpleText"] as? String)
            ?? ((object?["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined())
    }

    // MARK: Downloads

    private static func download(_ address: String, maximumBytes: Int) async -> Data? {
        guard let url = URL(string: address), url.scheme == "https" else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession(configuration: configuration).data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= maximumBytes else { return nil }
        return data
    }

    /// Small covers, one per row in order; a row whose cover failed has none.
    private static func covers(for urls: [URL?]) async -> [Data?] {
        await withTaskGroup(of: (Int, Data?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    guard let url, let data = await download(url.absoluteString, maximumBytes: NotchQueueSupport.maximumArtworkBytes),
                          !data.isEmpty else { return (index, nil) }
                    return (index, data)
                }
            }
            var result = [Data?](repeating: nil, count: urls.count)
            for await (index, data) in group { result[index] = data }
            return result
        }
    }
}
