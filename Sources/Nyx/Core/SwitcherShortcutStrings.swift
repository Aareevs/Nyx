struct SwitcherShortcutStrings {
    let allWindows: String
    let allWindowsCaption: String
}

extension FeatureStrings {
    static func switcherShortcuts(_ language: AppLanguage) -> SwitcherShortcutStrings {
        switch language {
        case .enUS:
            return .init(allWindows: "All windows",
                         allWindowsCaption: "Use a separate shortcut to cycle through windows from all apps in any layout. Your window filters still apply.")
        }
    }
}
