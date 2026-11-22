import AppKit
import MediaPlayer
import WebKit

/// Plays a saved playlist's songs inside Nyx, with no browser: YouTube's own
/// watch page runs in a web view kept in an invisible window off screen, so
/// nothing opens and YouTube's own rules (ads included) still apply. Nyx
/// keeps the order, moves to the next song when one ends and reads the
/// player's state once a second while it plays.
@MainActor
final class YouTubeInlinePlayer: NSObject, ObservableObject {
    static let shared = YouTubeInlinePlayer()

    @Published private(set) var playlist: YouTubeSavedPlaylist?
    @Published private(set) var videos: [YouTubeVideo] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isAd = false
    @Published private(set) var canSkipAd = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var loading = false

    var current: YouTubeVideo? { videos.indices.contains(index) ? videos[index] : nil }
    var isActive: Bool { playlist != nil }

    private var web: WKWebView?
    private var window: NSWindow?
    private var poll: Timer?
    /// The person paused: the player is not started again on its own.
    private var heldPaused = false
    private var loadedAt = Date.distantPast
    private var commandsRegistered = false
    private var artwork: MPMediaItemArtwork?
    private var artworkID: String?
    private var publishedSecond = -1

    func play(_ videos: [YouTubeVideo], from index: Int, in playlist: YouTubeSavedPlaylist) {
        guard videos.indices.contains(index) else { return }
        self.playlist = playlist
        self.videos = videos
        registerCommands()
        load(index)
    }

    func toggle() {
        guard web != nil else { return }
        heldPaused = isPlaying
        run(isPlaying ? "v.pause()" : "v.play()")
        isPlaying.toggle()
    }

    func next() {
        guard isActive else { return }
        if index + 1 < videos.count { load(index + 1) } else { stop() }
    }

    func previous() {
        guard isActive else { return }
        // A song a few seconds in starts over, as players do.
        if elapsed > 4 || index == 0 { run("v.currentTime = 0"); return }
        load(index - 1)
    }

    func skipAd() {
        run("var b = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern'); if (b) b.click()")
    }

    func seek(to seconds: Double) {
        guard duration > 0 else { return }
        run("v.currentTime = \(max(0, min(seconds, duration)))")
        elapsed = seconds
        publish()
    }

    func stop() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        artwork = nil
        artworkID = nil
        poll?.invalidate()
        poll = nil
        web?.stopLoading()
        web?.loadHTMLString("", baseURL: nil)
        web = nil
        window?.orderOut(nil)
        window = nil
        playlist = nil
        videos = []
        index = 0
        isPlaying = false
        isAd = false
        canSkipAd = false
        elapsed = 0
        duration = 0
        loading = false
    }

    // MARK: Web view

    private func load(_ position: Int) {
        guard let playlist, videos.indices.contains(position),
              let url = URL(string: "https://www.youtube.com/watch?v=\(videos[position].id)&list=\(playlist.id)") else { return }
        index = position
        heldPaused = false
        isPlaying = false
        isAd = false
        canSkipAd = false
        elapsed = 0
        duration = 0
        loading = true
        loadedAt = Date()
        prepare().load(URLRequest(url: url))
        startPolling()
    }

    private func prepare() -> WKWebView {
        if let web { return web }
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), configuration: configuration)
        web.customUserAgent = YouTubeAccount.userAgent
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 640, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.orderBack(nil)
        self.web = web
        self.window = window
        return web
    }

    private func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readState() }
        }
    }

    private static let stateScript = """
    (function(){var v=document.querySelector('video');var p=document.querySelector('#movie_player');
    if(!v)return '';var s=document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern');
    return JSON.stringify({paused:v.paused,ended:v.ended,t:v.currentTime||0,d:v.duration||0,
    ad:!!(p&&p.classList.contains('ad-showing')),skip:!!(s&&s.offsetParent),
    id:new URLSearchParams(location.search).get('v')||''});})()
    """

    private func readState() {
        guard let web else { return }
        web.evaluateJavaScript(Self.stateScript) { [weak self] result, _ in
            MainActor.assumeIsolated { self?.apply(result as? String ?? "") }
        }
    }

    private func apply(_ json: String) {
        guard let data = json.data(using: .utf8),
              let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // A page that never shows its player is moved past.
            if Date().timeIntervalSince(loadedAt) > 20 { next() }
            return
        }
        // YouTube moves on through the playlist by itself too; follow it.
        if let id = state["id"] as? String, id != current?.id,
           let moved = videos.firstIndex(where: { $0.id == id }) {
            index = moved
        }
        let paused = state["paused"] as? Bool ?? true
        let ad = state["ad"] as? Bool ?? false
        isAd = ad
        canSkipAd = state["skip"] as? Bool ?? false
        if !ad {
            elapsed = state["t"] as? Double ?? 0
            duration = state["d"] as? Double ?? 0
        }
        if state["ended"] as? Bool == true, !ad { next(); return }
        // The page does not start on its own; start it unless the person paused.
        if paused, !heldPaused { run("v.play()") }
        isPlaying = !paused
        loading = false
        publish()
    }

    private func run(_ statement: String) {
        web?.evaluateJavaScript("(function(){var v=document.querySelector('video'); if (v) { \(statement); } return '';})()")
    }

    // MARK: System Now Playing

    /// The song as the system's Now Playing shows it, which is where the
    /// island's player reads from; its buttons come back through these commands.
    private func registerCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let center = MPRemoteCommandCenter.shared()
        func handle(_ command: MPRemoteCommand, _ action: @escaping @MainActor (YouTubeInlinePlayer) -> Void) {
            command.isEnabled = true
            command.addTarget { _ in
                guard YouTubeInlinePlayer.shared.isActive else { return .noActionableNowPlayingItem }
                Task { @MainActor in action(YouTubeInlinePlayer.shared) }
                return .success
            }
        }
        handle(center.playCommand) { if !$0.isPlaying { $0.toggle() } }
        handle(center.pauseCommand) { if $0.isPlaying { $0.toggle() } }
        handle(center.togglePlayPauseCommand) { $0.toggle() }
        handle(center.nextTrackCommand) { $0.next() }
        handle(center.previousTrackCommand) { $0.previous() }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { event in
            guard YouTubeInlinePlayer.shared.isActive,
                  let event = event as? MPChangePlaybackPositionCommandEvent else { return .noActionableNowPlayingItem }
            let position = event.positionTime
            Task { @MainActor in YouTubeInlinePlayer.shared.seek(to: position) }
            return .success
        }
    }

    private func publish() {
        guard let current, !isAd else { return }
        // Once a second at most; the system counts the time on its own.
        let second = Int(elapsed)
        let info = MPNowPlayingInfoCenter.default()
        if second == publishedSecond, info.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == current.title,
           (info.playbackState == .playing) == isPlaying { return }
        publishedSecond = second
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyAlbumTitle: playlist?.title ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if duration > 0 { values[MPMediaItemPropertyPlaybackDuration] = duration }
        if artworkID == current.id, let artwork { values[MPMediaItemPropertyArtwork] = artwork }
        info.nowPlayingInfo = values
        info.playbackState = isPlaying ? .playing : .paused
        if artworkID != current.id { loadArtwork(for: current) }
    }

    private func loadArtwork(for video: YouTubeVideo) {
        artworkID = video.id
        artwork = nil
        guard let url = URL(string: "https://i.ytimg.com/vi/\(video.id)/mqdefault.jpg") else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data),
                  current?.id == video.id else { return }
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            publishedSecond = -1
            publish()
        }
    }
}
