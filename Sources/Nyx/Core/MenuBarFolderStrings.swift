import Foundation

struct MenuBarFolderStrings {
    let title: String
    let caption: String
    let empty: String
    let revealAll: String
    let hideAgain: String
    let turnOff: String
    let needsAccessibility: String
    let folderHelp: String
    let openNyx: String
    let insideTitle: String
    let panelCaption: String
    let refresh: String
    let moveOut: String
    let closeUndone: String
}

extension FeatureStrings {
    /// Only English is written so far; every language reads it until the
    /// translations are added.
    static func menuBarFolder(_ language: AppLanguage) -> MenuBarFolderStrings {
        .enUS
    }
}

extension MenuBarFolderStrings {
    static let enUS = MenuBarFolderStrings(
        title: "Menu bar folder",
        caption: "Adds a folder icon to the menu bar. To put an icon inside, click the folder to open it, then hold ⌘ and drag the icon to the left of the folder, and click the folder again to close it. To take an icon out, open the folder and drag it back to the right.",
        empty: "Nothing in the folder yet.",
        revealAll: "Show all icons",
        hideAgain: "Hide folder contents",
        turnOff: "Turn off menu bar folder",
        needsAccessibility: "Allow Nyx in Accessibility settings to open icons from the folder.",
        folderHelp: "Menu bar folder",
        openNyx: "Open Nyx",
        insideTitle: "In the folder",
        panelCaption: "To put an icon inside: click the folder to open it, hold ⌘ and drag the icon to the left of the folder, then click the folder to close it.",
        refresh: "Refresh",
        moveOut: "Move out of folder",
        closeUndone: "The folder stayed open because closing it would have hidden the folder icon too. Free some menu bar space and try again."
    )
}
