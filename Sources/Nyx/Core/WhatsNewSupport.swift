import Foundation

/// The short "What's new" window Nyx shows once, after an update. A fresh
/// install goes through onboarding instead and never sees it, and a version
/// with nothing written for it stays quiet.
enum WhatsNewInfo {
    struct Item: Identifiable, Equatable {
        let symbol: String
        let title: String
        let text: String
        var id: String { title }
    }

    /// The release page for `version`, where the full notes live.
    static func releaseURL(for version: String) -> URL {
        URL(string: "https://github.com/Aareevs/Nyx/releases/tag/v\(version)")
            ?? URL(string: "https://github.com/Aareevs/Nyx/releases/latest")!
    }

    /// What the window lists for `version`. Add a case when a release has
    /// something worth saying; a release without one shows no window.
    static func items(for version: String) -> [Item] {
        switch version {
        case "1.1.0":
            return [
                Item(symbol: "bubble.left.and.text.bubble.right", title: "Chat in the island",
                     text: "Talk to Claude, OpenAI, Gemini or NVIDIA with your own key, and send it images, PDFs, Word, Excel, CSV and text files."),
                Item(symbol: "play.rectangle", title: "YouTube playlists",
                     text: "Paste a YouTube or YouTube Music playlist link and play it inside Nyx, with no browser."),
                Item(symbol: "hand.tap", title: "Tap the notch (experimental)",
                     text: "Open the island with a fingertip tap. It is off by default: turn it on in Settings → Notch."),
                Item(symbol: "trash", title: "A better uninstaller",
                     text: "Select all, and an optional cleanup offer when you drag an app to the Trash."),
                Item(symbol: "film", title: "MP4 or MOV",
                     text: "Media tools can save a compressed video as MP4 or MOV."),
                Item(symbol: "wrench.and.screwdriver", title: "Fixes",
                     text: "Spotify, the island's player, Streaks, full-screen apps and the notch on newer macOS."),
            ]
        default:
            return []
        }
    }

    /// True once per update: the app is newer than the version that last ran,
    /// this version has something to say, and it was not already shown.
    static func shouldShow(appVersion: String, previousVersion: String?, shownVersion: String?) -> Bool {
        guard shownVersion != appVersion,
              BrightnessUpdatePromptInfo.isUpgrade(appVersion: appVersion, previousVersion: previousVersion)
        else { return false }
        return !items(for: appVersion).isEmpty
    }
}
