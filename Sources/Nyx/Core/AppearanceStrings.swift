import Foundation

struct AppearanceStrings {
    let label: String
    let system: String
    let light: String
    let dark: String
    let liquidGlass: String
}

extension FeatureStrings {
    static func appearance(_ language: AppLanguage) -> AppearanceStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension AppearanceStrings {
    static let enUS = AppearanceStrings(
        label: "Appearance",
        system: "System",
        light: "Light",
        dark: "Dark",
        liquidGlass: "Liquid Glass"
    )













}
