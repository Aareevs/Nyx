import Foundation

struct MouseButtonFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enableLabel: String
    let enableCaption: String
    let addButton: String
    let captureWaiting: String
    let captureCancel: String
    let captureBlind: String
    let captureUnsupported: String
    let captureWheel: String
    let captureExists: String
    let captureHint: String
    let middleButtonName: String
    let backButtonName: String
    let forwardButtonName: String
    let otherButtonFormat: String      // "Button %d"
    let setShortcutButton: String
    let removeButton: String
    let emptyCaption: String
    let rowWheelNote: String
    let manageButton: String
    let panelCaption: String
    let sideWheelLeftName: String
    let sideWheelRightName: String
    let spacesEnableLabel: String
    let spacesEnableCaption: String
    let spacesPickButton: String
    let spacesShortcutsOffNote: String
    // The drag capture cannot borrow the shortcut capture's strings: it
    // refuses the side wheel by design, and its refusals must not point at a
    // list that is off screen with the shortcut switch off. New fields, so the
    // memberwise initializer makes a missing language a compile error.
    let spacesCaptureWaiting: String
    let spacesCaptureUnsupported: String
    let spacesCaptureExists: String
    let spacesFollowsDragLabel: String
    let spacesFollowsDragCaption: String
}

extension FeatureStrings {
    static func mouseButtons(_ language: AppLanguage) -> MouseButtonFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension MouseButtonFeatureStrings {
    static let enUS = MouseButtonFeatureStrings(
        pageTitle: "Mouse button shortcuts",
        hubDescription: "Extra buttons and side-wheel directions press a key combination you choose.",
        enableLabel: "Use extra buttons as shortcuts",
        enableCaption: "Each extra button or side-wheel direction can press a key combination for you. While it has a shortcut, it stops doing what it did before.",
        addButton: "Add a button or side wheel",
        captureWaiting: "Now press an extra button or move the side wheel.",
        captureCancel: "Cancel",
        captureBlind: "Nyx cannot watch the mouse right now.",
        captureUnsupported: "That input cannot take a shortcut. Use an extra button or a side-wheel direction.",
        captureWheel: "That button already opens the radial menu. Pick another one, or free it there first.",
        captureExists: "That button or direction is already on the list below.",
        captureHint: "If nothing happens, your mouse’s own software may already be using that control.",
        middleButtonName: "Middle button",
        backButtonName: "Back side button",
        forwardButtonName: "Forward side button",
        otherButtonFormat: "Button %d",
        setShortcutButton: "Set shortcut",
        removeButton: "Remove",
        emptyCaption: "No shortcuts yet. Add a button or side-wheel direction.",
        rowWheelNote: "This button opens the radial menu now, so the shortcut waits.",
        manageButton: "Set up…",
        panelCaption: "Extra buttons and side-wheel directions press key combinations you choose.",
        sideWheelLeftName: "Side wheel left",
        sideWheelRightName: "Side wheel right",
        spacesEnableLabel: "Switch Spaces by dragging a button",
        spacesEnableCaption: "Hold the chosen button and drag: left or right moves one Space over, up opens Mission Control, down opens App Exposé. A short click still does what it always did.",
        spacesPickButton: "Choose a button",
        spacesShortcutsOffNote: "The Mission Control keyboard shortcuts are switched off in System Settings, so this gesture has nothing to ask for.",
        spacesCaptureWaiting: "Now press the middle button or an extra button.",
        spacesCaptureUnsupported: "That input cannot be held for a drag. Use the middle button or an extra button.",
        spacesCaptureExists: "That button already has a shortcut. Pick another one.",
        spacesFollowsDragLabel: "Spaces follow the drag",
        spacesFollowsDragCaption: "Dragging right brings the Space on the left, the way a trackpad swipe carries it along with your fingers."
    )













}
