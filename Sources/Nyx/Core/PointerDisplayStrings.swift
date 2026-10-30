struct PointerDisplayStrings {
    let title: String
    let caption: String

    static func localized(_ language: AppLanguage) -> PointerDisplayStrings {
        switch language {
        case .enUS: return .init(title: "Move pointer to next display", caption: "Puts the pointer in the center of the next display.")
        }
    }
}
