import Foundation

struct NotchTeleprompterStrings {
    let title: String
    let description: String
    let summary: String
    /// "Line 4 of 15".
    let lineFormat: String
    let start: String
    let pause: String
    let resume: String
    let restart: String
    let previousLine: String
    let nextLine: String
    let wpm: String
    let slower: String
    let faster: String
    let editScript: String
    let editorTitle: String
    let back: String
    let done: String
    let paste: String
    let clear: String
    let pasteScript: String
    let writeScript: String
    let empty: String
    let emptyHint: String
    let placeholder: String
    /// "42 words".
    let wordsFormat: String
    let hiddenFromRecordings: String
    let visibleInRecordings: String
    let hideSetting: String
    let hideHint: String
    /// Names of the three sizes, shown on the resize control.
    let sizeMedium: String
    let sizeLarge: String
    /// "Size: Medium. Tap to change."
    let resizeFormat: String

    func sizeName(_ size: NotchTeleprompterSize) -> String {
        switch size {
        case .medium: return sizeMedium
        case .large: return sizeLarge
        }
    }
}

extension FeatureStrings {
    static func notchTeleprompter(_ language: AppLanguage) -> NotchTeleprompterStrings {
        switch language {
        case .enUS: return NotchTeleprompterStrings(
            title: "Teleprompter",
            description: "Read a script from the Dynamic Island while you record or present. Type it or paste it, set the speed, and keep the island out of screen recordings.",
            summary: "A scrolling script to read from, with speed control.",
            lineFormat: "Line %d of %d",
            start: "Start",
            pause: "Pause",
            resume: "Resume",
            restart: "Restart",
            previousLine: "Previous line",
            nextLine: "Next line",
            wpm: "WPM",
            slower: "Slower",
            faster: "Faster",
            editScript: "Edit script",
            editorTitle: "Script",
            back: "Back to teleprompter",
            done: "Done",
            paste: "Paste",
            clear: "Clear",
            pasteScript: "Paste script",
            writeScript: "Write script",
            empty: "No script yet",
            emptyHint: "Write one here, or paste a script you already have.",
            placeholder: "Type or paste your script. Each line becomes a line on the island.",
            wordsFormat: "%d words",
            hiddenFromRecordings: "Hidden from screen recordings",
            visibleInRecordings: "Visible in screen recordings",
            hideSetting: "Hide from screen recordings",
            hideHint: "Keeps the island out of screen recordings and screenshots while the teleprompter is open. Some screen-sharing apps may still show it.",
            sizeMedium: "Medium",
            sizeLarge: "Large",
            resizeFormat: "Size: %@. Click to change.")
        }
    }
}
