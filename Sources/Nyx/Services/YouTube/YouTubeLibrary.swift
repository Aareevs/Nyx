import AppKit
import Foundation

/// YouTube and YouTube Music playlists saved by their links. The list is
/// kept in a private file on this Mac and never synced. A playlist's songs
/// come from its public page, so public and unlisted playlists work and
/// private ones do not. Songs play inside Nyx, with no browser.
@MainActor
final class YouTubeLibrary: ObservableObject {
    static let shared = YouTubeLibrary()

    @Published private(set) var playlists: [YouTubeSavedPlaylist] = []
    @Published private(set) var videos: [YouTubeVideo] = []
    @Published private(set) var loading = false
    @Published private(set) var message: String?

    private let fileURL: URL?

    private init() {
        fileURL = PrivateFileStore.containerURL?
            .appendingPathComponent("YouTube", isDirectory: true)
            .appendingPathComponent("Playlists.json")
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([YouTubeSavedPlaylist].self, from: data) {
            playlists = saved
        }
    }

    func clearMessage() { message = nil }

    /// Saves the playlist a link names, after reading its page for its name
    /// and songs. Answers whether it was added.
    @discardableResult
    func add(link: String) async -> Bool {
        guard let parsed = YouTubePlaylistSupport.parse(link) else {
            message = "That is not a YouTube or YouTube Music playlist link."
            return false
        }
        if playlists.contains(where: { $0.id == parsed.id }) {
            message = "That playlist is already here."
            return false
        }
        loading = true
        message = nil
        defer { loading = false }
        guard let page = await fetch(parsed.id) else {
            message = "Couldn't open that playlist. Check it is public or unlisted, and that you're online."
            return false
        }
        guard !page.videos.isEmpty else {
            message = "That playlist is empty or private. Set it to public or unlisted on YouTube."
            return false
        }
        playlists.insert(YouTubeSavedPlaylist(id: parsed.id, title: page.title ?? "YouTube playlist",
                                              music: parsed.music, count: page.videos.count,
                                              firstVideo: page.videos.first?.id), at: 0)
        save()
        return true
    }

    func remove(_ playlist: YouTubeSavedPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func move(_ playlist: YouTubeSavedPlaylist, by step: Int) {
        guard let from = playlists.firstIndex(of: playlist), playlists.indices.contains(from + step) else { return }
        playlists.swapAt(from, from + step)
        save()
    }

    func loadVideos(of playlist: YouTubeSavedPlaylist) async {
        videos = []
        loading = true
        message = nil
        defer { loading = false }
        guard let page = await fetch(playlist.id) else {
            message = "Couldn't load this playlist. It may have been made private or you're offline."
            return
        }
        videos = page.videos
        // The saved name and size follow the playlist as it changes on YouTube.
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            if let title = page.title { playlists[index].title = title }
            playlists[index].count = page.videos.count
            playlists[index].firstVideo = page.videos.first?.id ?? playlists[index].firstVideo
            save()
        }
    }

    /// Plays the playlist inside Nyx, from the chosen song or its first.
    func play(_ video: YouTubeVideo?, in playlist: YouTubeSavedPlaylist) {
        let start = video.flatMap { video in videos.firstIndex { $0.id == video.id } } ?? 0
        if !videos.isEmpty {
            YouTubeInlinePlayer.shared.play(videos, from: start, in: playlist)
            return
        }
        Task {
            await loadVideos(of: playlist)
            YouTubeInlinePlayer.shared.play(videos, from: 0, in: playlist)
        }
    }

    private func fetch(_ id: String) async -> (title: String?, videos: [YouTubeVideo])? {
        guard let address = YouTubePlaylistSupport.pageURL(id)?.absoluteString,
              let data = await NotchWebQueue.download(address, maximumBytes: 8_000_000),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var seen = Set<String>()
        let videos = NotchWebQueue.playlistEntries(in: html).compactMap { entry -> YouTubeVideo? in
            guard seen.insert(entry.id).inserted else { return nil }
            return YouTubeVideo(id: entry.id, title: entry.title, artist: YouTubePlaylistSupport.artist(entry.artist))
        }
        return (YouTubePlaylistSupport.title(in: html), videos)
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(playlists) else { return }
        PrivateFileStore.createDirectory(at: fileURL.deletingLastPathComponent())
        PrivateFileStore.write(data, to: fileURL)
    }
}
