import Foundation

struct NotchTourStrings {
    let preview: String
    let caption: String
}

extension FeatureStrings {
    static func notchTour(_ language: AppLanguage) -> NotchTourStrings {
        switch language {
        case .enUS: return NotchTourStrings(preview: "Preview for 3.4",
            caption: "Control music, timers, volume and brightness. Choose the floating shortcuts you use most.")
        }
    }
}
