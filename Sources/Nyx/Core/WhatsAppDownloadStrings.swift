import Foundation

struct WhatsAppDownloadStrings {
    let title: String
    let hubDescription: String
    let intro: String
    let automatic: String
    let automaticCaption: String
    let folder: String
    let accessReady: String
    let accessDenied: String
    let fileTypes: String
    let allTypes: String
    let image: String
    let video: String
    let audio: String
    let document: String
    let archive: String
    let other: String
    let retention: String
    let retentionCaption: String
    let daysFormat: String
    let manualIntro: String
    let noFiles: String
    let resultsFormat: String
    let selectRules: String
    let cleanSelectedFormat: String
    let keep: String
    let manageAgain: String
    let activity: String
    let neverRun: String
    let lastRunFormat: String
    let nextRunFormat: String
    let firstTitle: String
    let firstMessageFormat: String
    let futureOnly: String
    let includeExisting: String
    let trashNote: String
    let localNote: String
    let notificationTitle: String
    let notificationFormat: String
    let scanFailed: String
    let manageButton: String

    static func localized(_ language: AppLanguage) -> WhatsAppDownloadStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension WhatsAppDownloadStrings {
    static let enUS = WhatsAppDownloadStrings(
        title: "WhatsApp downloads",
        hubDescription: "Keeps WhatsApp files in Downloads under control",
        intro: "Finds files that macOS confirms came from WhatsApp. File contents and chats are never read.",
        automatic: "Clean up automatically",
        automaticCaption: "Checks once a day and sends matching files older than your limit to the Trash.",
        folder: "Watched folder",
        accessReady: "Downloads is accessible",
        accessDenied: "Nyx cannot access Downloads. Allow it in Files & Folders.",
        fileTypes: "File types",
        allTypes: "All",
        image: "Images",
        video: "Videos",
        audio: "Audio and voice notes",
        document: "Documents",
        archive: "Archives",
        other: "Other",
        retention: "Keep for",
        retentionCaption: "Recently edited files wait for the full period again.",
        daysFormat: "%d days",
        manualIntro: "Scan at any time. The initial selection follows your types and age limit; you can review every confirmed file.",
        noFiles: "No confirmed WhatsApp files found in Downloads.",
        resultsFormat: "%1$d confirmed files · %2$@",
        selectRules: "Select by my rules",
        cleanSelectedFormat: "Move %1$d to Trash · %2$@",
        keep: "Keep",
        manageAgain: "Manage again",
        activity: "Activity",
        neverRun: "No cleanup has run yet.",
        lastRunFormat: "Last cleanup %@: %d files · %@ · %d failed",
        nextRunFormat: "Next automatic check %@.",
        firstTitle: "What about existing files?",
        firstMessageFormat: "%d existing files already match your rules. Choose whether automation may manage them or only future downloads.",
        futureOnly: "Only future downloads",
        includeExisting: "Include existing files",
        trashNote: "Files are moved to the Trash and remain recoverable until you empty it.",
        localNote: "Only local file metadata is inspected. Nyx never reads chats or file contents.",
        notificationTitle: "WhatsApp cleanup",
        notificationFormat: "%1$d files (%2$@) moved to the Trash. %3$d failed.",
        scanFailed: "Downloads could not be scanned. Check Files & Folders in System Settings.",
        manageButton: "Manage…"
    )














    private struct OperationalStrings {
        let automaticCaption: String
        let retentionCaption: String
        let manualIntro: String
        let resultsFormat: String
        let selectRules: String
        let cleanSelectedFormat: String
        let lastRunFormat: String
        let nextRunFormat: String
        let firstMessageFormat: String
        let localNote: String
        let notificationFormat: String
        let scanFailed: String
        let manageButton: String
    }

    private static func operational(_ language: AppLanguage) -> OperationalStrings {
        switch language {
        case .enUS: return OperationalStrings(
            automaticCaption: enUS.automaticCaption, retentionCaption: enUS.retentionCaption,
            manualIntro: enUS.manualIntro, resultsFormat: enUS.resultsFormat,
            selectRules: enUS.selectRules, cleanSelectedFormat: enUS.cleanSelectedFormat,
            lastRunFormat: enUS.lastRunFormat, nextRunFormat: enUS.nextRunFormat,
            firstMessageFormat: enUS.firstMessageFormat, localNote: enUS.localNote,
            notificationFormat: enUS.notificationFormat, scanFailed: enUS.scanFailed, manageButton: enUS.manageButton)
        }
    }

    private static func translated(language: AppLanguage,
                                   title: String, hub: String, intro: String,
                                   automatic: String, folder: String, accessReady: String,
                                   accessDenied: String, types: String, all: String,
                                   image: String, video: String, audio: String,
                                   document: String, archive: String, other: String,
                                   retention: String, days: String, noFiles: String,
                                   keep: String, manage: String, activity: String,
                                   never: String, future: String, existing: String,
                                   firstTitle: String, trash: String,
                                   notificationTitle: String) -> WhatsAppDownloadStrings {
        let value = operational(language)
        return WhatsAppDownloadStrings(
            title: title, hubDescription: hub, intro: intro,
            automatic: automatic, automaticCaption: value.automaticCaption,
            folder: folder, accessReady: accessReady, accessDenied: accessDenied,
            fileTypes: types, allTypes: all, image: image, video: video, audio: audio,
            document: document, archive: archive, other: other,
            retention: retention, retentionCaption: value.retentionCaption, daysFormat: days,
            manualIntro: value.manualIntro, noFiles: noFiles, resultsFormat: value.resultsFormat,
            selectRules: value.selectRules, cleanSelectedFormat: value.cleanSelectedFormat,
            keep: keep, manageAgain: manage, activity: activity, neverRun: never,
            lastRunFormat: value.lastRunFormat, nextRunFormat: value.nextRunFormat,
            firstTitle: firstTitle, firstMessageFormat: value.firstMessageFormat,
            futureOnly: future, includeExisting: existing, trashNote: trash,
            localNote: value.localNote, notificationTitle: notificationTitle,
            notificationFormat: value.notificationFormat, scanFailed: value.scanFailed, manageButton: value.manageButton)
    }
}
