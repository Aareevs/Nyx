struct WindowStageManagerStrings {
    let title: String
    let caption: String

    static func localized(_ language: AppLanguage) -> WindowStageManagerStrings {
        switch language {
        case .enUS: return .init(title: "Reserve space for Stage Manager", caption: "Keep recent apps visible when maximizing or arranging windows, while Stage Manager and Show recent apps are on.")
        }
    }
}
