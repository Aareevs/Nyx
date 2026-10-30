import Foundation

struct RecorderExportStrings {
    let speed: String
    let custom: String
    let duration: String
    let previewNote: String
}

extension FeatureStrings {
    static func recorderExport(_ language: AppLanguage) -> RecorderExportStrings {
        switch language {
        case .enUS:
            return RecorderExportStrings(
                speed: "Export speed", custom: "Custom speed", duration: "Export duration",
                previewNote: "Applies to video and GIF. The editing preview stays at 1×; the original recording is unchanged.")
        }
    }
}
