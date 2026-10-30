import Foundation

struct NotchLockScreenStrings {
    /// The name System Settings gives its own Lock Screen pane.
    let title: String
    let show: String
    let showHint: String
    let sounds: String
    let soundsHint: String
    /// Beside the names of the agents working while the Mac is locked.
    let working: String
}

extension FeatureStrings {
    static func notchLockScreen(_ language: AppLanguage) -> NotchLockScreenStrings {
        switch language {
        case .enUS: return NotchLockScreenStrings(
            title: "Lock Screen",
            show: "Show on the Lock Screen",
            showHint: "Music and the Dynamic Island’s activities, like a timer, AI agents, downloads and your next event, appear above the password field. Anyone who can see your screen can read them.",
            sounds: "Lock and unlock sounds",
            soundsHint: "Play the macOS padlock sound when your Mac locks and unlocks.",
            working: "Working")
        }
    }
}
