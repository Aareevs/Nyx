import Foundation

enum YouTubePlaylistTests {
    static func run(_ suite: TestSuite) {
        let id = "PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG"
        suite.expect(YouTubePlaylistSupport.parse("https://www.youtube.com/playlist?list=\(id)").map { $0.id == id && !$0.music } == true,
                     "a YouTube playlist link names its playlist")
        suite.expect(YouTubePlaylistSupport.parse("https://music.youtube.com/playlist?list=\(id)&si=abc").map { $0.id == id && $0.music } == true,
                     "a YouTube Music link is kept as YouTube Music's")
        suite.expect(YouTubePlaylistSupport.parse("youtube.com/watch?v=dQw4w9WgXcQ&list=\(id)&index=3")?.id == id,
                     "a song inside a playlist names the playlist, without a scheme too")
        suite.expect(YouTubePlaylistSupport.parse("https://youtu.be/dQw4w9WgXcQ?list=\(id)")?.id == id,
                     "a short youtu.be link with a playlist works")
        suite.expect(YouTubePlaylistSupport.parse("  \(id)\n")?.id == id, "a bare playlist id works")
        suite.expect(YouTubePlaylistSupport.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == nil
                     && YouTubePlaylistSupport.parse("https://example.com/playlist?list=\(id)") == nil
                     && YouTubePlaylistSupport.parse("https://www.youtube.com/watch?v=x&list=RDdQw4w9WgXcQ") == nil,
                     "a single video, another site and a personal mix are not playlists to save")
        suite.expect(YouTubePlaylistSupport.validID("RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs"),
                     "YouTube Music's public album lists are allowed")

        let video = YouTubeSavedPlaylist(id: id, title: "Mix", music: false, count: 3, firstVideo: "dQw4w9WgXcQ")
        suite.expect(YouTubePlaylistSupport.watchURL(playlist: video, video: nil)?.absoluteString
                     == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=\(id)",
                     "a YouTube playlist plays from its first song")
        var music = video
        music.music = true
        suite.expect(YouTubePlaylistSupport.watchURL(playlist: music, video: "abcdefghijk")?.absoluteString
                     == "https://music.youtube.com/watch?v=abcdefghijk&list=\(id)",
                     "a YouTube Music playlist plays the chosen song in YouTube Music")
        music.firstVideo = nil
        suite.expect(YouTubePlaylistSupport.watchURL(playlist: music, video: nil)?.absoluteString
                     == "https://music.youtube.com/playlist?list=\(id)",
                     "a playlist with no known song opens its page")

        suite.expect(YouTubePlaylistSupport.title(in: #"<meta property="og:title" content="Late Night &amp; Chill">"#) == "Late Night & Chill"
                     && YouTubePlaylistSupport.title(in: "<title>Road Trip - YouTube</title>") == "Road Trip"
                     && YouTubePlaylistSupport.title(in: "<title>YouTube</title>") == nil,
                     "a playlist's name comes from its page, without the site's name")
        suite.expect(YouTubePlaylistSupport.artist("Daft Punk - Topic") == "Daft Punk"
                     && YouTubePlaylistSupport.artist("Some Channel") == "Some Channel",
                     "a YouTube Music channel's ' - Topic' is not part of the artist")
    }
}
