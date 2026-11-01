import Foundation

struct NotchMusicExtrasStrings {
    let lyrics: String
    let lyricsDescription: String
    let enableLyrics: String
    let online: String
    let onlineHint: String
    let importLyrics: String
    let importHint: String
    let loading: String
    let unavailable: String
    let failed: String
    let retry: String
    let instrumental: String
    let waiting: String
    let noPosition: String
    let offset: String
    let earlier: String
    let later: String
    let reset: String
    let actionFailed: String
    let playbackFailed: String
    let allowPlayback: String
    let automationPermission: String
    let automationExplanation: String
    let queue: String
    let queueDescription: String
    let enableQueue: String
    let queueUnavailable: String
    let queueEmpty: String
    let queueNeedsOnline: String
    let queueTurnOn: String
    let queueNeedsSpotify: String
    let queueSignIn: String
    let queueNoPlaylist: String
    let queueNeedsScripting: String
    let queueWebFailed: String
    let onlineQueue: String
    let onlineQueueHint: String
    let playNow: String
    let refresh: String
    let openPlayer: String
    let playbackSource: String
    let automaticSource: String
    let includeOtherPlayers: String
    let liveEqualizer: String
    /// One line for the features hub, where the hint below would not fit.
    let liveEqualizerDescription: String
    let liveEqualizerHint: String
    let liveEqualizerUnavailable: String
    let shuffle: String
    let showVolume: String
    let preferredPlayer: String
    let preferredPlayerHint: String
    /// "Open Spotify", with the app's name in place of %@.
    let openNamedPlayer: String
    let browserCovers: String
    let browserCoversHint: String
}

extension FeatureStrings {
    static func notchMusicExtras(_ language: AppLanguage) -> NotchMusicExtrasStrings {
        switch language {
        case .enUS: return NotchMusicExtrasStrings(
            lyrics: "Lyrics",
            lyricsDescription: "Follow the lyrics of the current song in the Dynamic Island.",
            enableLyrics: "Show lyrics",
            online: "Find lyrics online",
            onlineHint: "While lyrics are open, send the song title, artist, album and duration to lrclib.net. Imported lyrics stay on this Mac. Song titles, artist names and albums may also be checked with musicbrainz.org.",
            importLyrics: "Import lyrics…",
            importHint: "Choose timed lyrics for the current recording. They are kept only while this song is open.",
            loading: "Loading lyrics…",
            unavailable: "No matching lyrics for this recording.",
            failed: "Could not load the lyrics.",
            retry: "Try again",
            instrumental: "Instrumental",
            waiting: "Waiting for the first verse",
            noPosition: "The player does not share its position.",
            offset: "Timing",
            earlier: "Earlier",
            later: "Later",
            reset: "Reset",
            actionFailed: "The player did not switch to this song.",
            playbackFailed: "Could not change playback.",
            allowPlayback: "Allow playback control",
            automationPermission: "Playback automation",
            automationExplanation: "Some music apps require permission for their playback controls. Authorize the selected player from Dynamic Island; access is granted separately for each app.",
            queue: "Up next",
            queueDescription: "See the actual upcoming songs shared by your player.",
            enableQueue: "Show upcoming songs",
            queueUnavailable: "This player does not share its upcoming songs.",
            queueEmpty: "No upcoming songs",
            queueNeedsOnline: "Spotify and YouTube share their upcoming songs only online. Turn on the lookup to see them.",
            queueTurnOn: "Turn on",
            queueNeedsSpotify: "You need a Spotify Premium account, and the developer has to add you first. Once they have, sign in to Spotify here.",
            queueSignIn: "Sign in to Spotify",
            queueNoPlaylist: "This video is not in a YouTube playlist, so there is no list of what comes next.",
            queueNeedsScripting: "To list a YouTube playlist, turn on “Allow JavaScript from Apple Events” in your browser’s View ▸ Developer menu, then press Retry.",
            queueWebFailed: "Could not load the upcoming songs. Try again in a moment.",
            onlineQueue: "Look up Spotify and YouTube queues online",
            onlineQueueHint: "Spotify’s queue comes from your Spotify account. For YouTube, Nyx reads the playing tab’s address from your browser and loads that playlist’s public page. Nothing is stored.",
            playNow: "Play now",
            refresh: "Refresh",
            openPlayer: "Open player",
            playbackSource: "Playback source",
            automaticSource: "Automatic",
            includeOtherPlayers: "Automatically include videos and other apps",
            liveEqualizer: "Bars follow the music",
            liveEqualizerDescription: "Move the Dynamic Island bars with the sound your player makes.",
            liveEqualizerHint: "Listens to the player’s own audio output to move the bars. macOS asks once to allow system audio recording. Nothing is stored or sent. Without it, the bars keep their usual motion.",
            liveEqualizerUnavailable: "Needs macOS 14.4 or later.",
            shuffle: "Shuffle",
            showVolume: "Show volume in the player",
            preferredPlayer: "Open when nothing is playing",
            preferredPlayerHint: "The cover and the playback buttons open this app. Automatic opens the music app that played last, then Spotify or Apple Music.",
            openNamedPlayer: "Open %@",
            browserCovers: "Find covers for Firefox and Zen",
            browserCoversHint: "When Firefox, Zen or another Firefox-based browser plays without a sharp cover, read its saved session on this Mac to find the song’s YouTube tab and load its thumbnail from i.ytimg.com. If no tab shows the song but a YouTube Music tab is open, send the song title, artist and region to itunes.apple.com and load the album art from mzstatic.com.")
        }
    }
}
