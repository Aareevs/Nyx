import Foundation

/// A YouTube or YouTube Music playlist the person saved by its link. Only the
/// link's parts and what its public page showed are kept, on this Mac.
struct YouTubeSavedPlaylist: Codable, Identifiable, Equatable {
    /// The playlist's id, the `list` part of its link.
    let id: String
    var title: String
    /// Saved from music.youtube.com, so it plays there.
    var music: Bool
    var count: Int
    var firstVideo: String?
}

struct YouTubeVideo: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
}

enum YouTubePlaylistSupport {
    /// The playlist a pasted link names, and whether it is YouTube Music's.
    /// Accepts youtube.com, music.youtube.com, m.youtube.com and youtu.be
    /// links, or a bare playlist id.
    static func parse(_ text: String) -> (id: String, music: Bool)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if validID(trimmed), !trimmed.contains("/") { return (trimmed, false) }
        let address = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let parts = URLComponents(string: address), let host = parts.host?.lowercased(),
              host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com"),
              let list = parts.queryItems?.first(where: { $0.name == "list" })?.value,
              validID(list) else { return nil }
        return (list, host == "music.youtube.com")
    }

    static func validID(_ id: String) -> Bool {
        // Mixes made for one person ("RD…") change on every visit and have no
        // public page; "WL" and "LL" are private to the signed-in account.
        // YouTube Music's own album and chart lists ("RDCLAK…") are public.
        guard id.range(of: #"^[A-Za-z0-9_-]{10,80}$"#, options: .regularExpression) != nil else { return false }
        return !id.hasPrefix("RD") || id.hasPrefix("RDCLAK")
    }

    static func pageURL(_ id: String) -> URL? {
        URL(string: "https://www.youtube.com/playlist?list=\(id)")
    }

    /// Where a playlist plays: its first song, or the one chosen, in the
    /// player the playlist was saved from.
    static func watchURL(playlist: YouTubeSavedPlaylist, video: String?) -> URL? {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = playlist.music ? "music.youtube.com" : "www.youtube.com"
        if let video = video ?? playlist.firstVideo {
            parts.path = "/watch"
            parts.queryItems = [.init(name: "v", value: video), .init(name: "list", value: playlist.id)]
        } else {
            parts.path = "/playlist"
            parts.queryItems = [.init(name: "list", value: playlist.id)]
        }
        return parts.url
    }

    static func thumbnail(_ video: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(video)/mqdefault.jpg")
    }

    /// The playlist's name from its public page.
    static func title(in html: String) -> String? {
        let patterns = [#"<meta property="og:title" content="([^"]*)""#, #"<title>([^<]*)</title>"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            var title = decodeEntities(String(html[range])).trimmingCharacters(in: .whitespacesAndNewlines)
            if title.hasSuffix(" - YouTube") { title.removeLast(" - YouTube".count) }
            if !title.isEmpty, title != "YouTube" { return title }
        }
        return nil
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    /// Who made a song: a YouTube Music channel ends in " - Topic".
    static func artist(_ byline: String) -> String {
        byline.hasSuffix(" - Topic") ? String(byline.dropLast(" - Topic".count)) : byline
    }
}
