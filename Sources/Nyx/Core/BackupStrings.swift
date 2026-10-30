import Foundation

/// Strings for the settings backup (export and import on the Advanced page).
/// Same contract as the other FeatureStrings structs: memberwise init in
/// declaration order, one static per language, all in this file.
struct BackupFeatureStrings {
    let title: String
    let description: String
    let exportButton: String
    let importButton: String
    let exported: String
    let exportFailed: String
    let importConfirmTitle: String
    let importConfirmBody: String
    let importMissingIslandBody: String
    let importAction: String
    let invalidFile: String
}

extension FeatureStrings {
    static func backup(_ language: AppLanguage) -> BackupFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension BackupFeatureStrings {
}

extension BackupFeatureStrings {
    static let enUS = BackupFeatureStrings(
        title: "Backup",
        description: "Take your setup to another Mac: export every preference to a file and import it there. Your Scratchpad notes, clipboard history, Shelf items and system permissions never leave this Mac.",
        exportButton: "Export settings…",
        importButton: "Import settings…",
        exported: "Backup saved",
        exportFailed: "Could not save the backup.",
        importConfirmTitle: "Import these settings?",
        importConfirmBody: "Your current settings are replaced by the file’s and the app restarts. Nothing else on this Mac is touched.",
        importMissingIslandBody: "This backup has no Dynamic Island settings. This Mac’s island settings will be kept. Re-export with Nyx 3.4 or newer on the other Mac to copy them. Other settings will be imported and the app will restart.",
        importAction: "Import and restart",
        invalidFile: "This file is not a valid Nyx backup."
    )












}
