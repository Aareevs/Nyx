struct SettingsNavigationStrings {
    let go: String
    let back: String
    let forward: String
    /// The names macOS gives its own sidebar command in each language.
    let showSidebar: String
    let hideSidebar: String
    let help: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return Self(go: "Go", back: "Back", forward: "Forward",
                        showSidebar: "Show Sidebar", hideSidebar: "Hide Sidebar", help: "Help")
        }
    }
}
