struct NotchLowBatteryStrings {
    let title: String
    let caption: String
    let threshold: String
    let early: String
    let earlyCaption: String
    let earlyThreshold: String
    let menuBar: String

    static func localized(_ language: AppLanguage) -> NotchLowBatteryStrings {
        switch language {
        case .enUS:
            return .init(title: "Turn red when low", caption: "Shows the charge in red at or below this level while on battery.",
                         threshold: "Red level", early: "Turn amber first",
                         earlyCaption: "Shows the charge in amber at or below a higher level, as an early warning.",
                         earlyThreshold: "Amber level", menuBar: "Also in the menu bar")
        }
    }
}
