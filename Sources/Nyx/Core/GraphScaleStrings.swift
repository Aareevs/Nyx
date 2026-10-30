struct GraphScaleStrings {
    let title: String

    static func localized(_ language: AppLanguage) -> GraphScaleStrings {
        switch language {
        case .enUS: return .init(title: "Show graph scale")
        }
    }
}
