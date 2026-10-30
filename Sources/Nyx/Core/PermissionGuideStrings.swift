import Foundation

/// Strings for the floating permission guide: the little card that walks the
/// person through System Settings and notices the grant by itself. Same
/// contract as the other FeatureStrings structs: memberwise init in
/// declaration order, one static per language, all in this file.
struct PermissionGuideStrings {
    let title: String
    let stepOpen: String
    let stepToggle: String
    let stepReturn: String
    let waiting: String
    let granted: String
    let closeHelp: String
    /// Shown once the wait has gone on a while: the usual cause is an entry
    /// left by an earlier copy of the app, which macOS shows as on but no
    /// longer honours.
    let staleHint: String
    let startOver: String
    let relaunch: String
}

extension FeatureStrings {
    static func permissionGuide(_ language: AppLanguage) -> PermissionGuideStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension PermissionGuideStrings {
}

extension PermissionGuideStrings {
    static let enUS = PermissionGuideStrings(
        title: "One step left",
        stepOpen: "macOS opened System Settings on the right list.",
        stepToggle: "Turn Nyx on in that list.",
        stepReturn: "Come back. This card notices by itself.",
        waiting: "Waiting for the permission…",
        granted: "Permission granted!",
        closeHelp: "Close",
        staleHint: "Already on in that list? That entry belongs to an earlier copy of the app. Start over to replace it.",
        startOver: "Start over",
        relaunch: "Relaunch to apply"
    )












}
