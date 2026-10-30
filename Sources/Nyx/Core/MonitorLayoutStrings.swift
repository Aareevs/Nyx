import Foundation

struct MonitorLayoutFeatureStrings {
    /// Heading for the settings shared by the menu bar and the panel.
    let shared: String
    /// Names the bytes or bits choice for live network speeds, as its
    /// settings row and as the panel button that flips it.
    let networkSpeedUnit: String
}

extension FeatureStrings {
    static func monitorLayout(_ language: AppLanguage) -> MonitorLayoutFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension MonitorLayoutFeatureStrings {
    static let enUS = MonitorLayoutFeatureStrings(
        shared: "Readings and alerts",
        networkSpeedUnit: "Network speed unit"
    )














}
