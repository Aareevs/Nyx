import Foundation

/// Plain-language copy for the General page: one short line per control and
/// one per panel section, so the page explains itself without paragraphs.
struct GeneralSettingsStrings {
    let pageDescription: String
    let appearanceCaption: String
    let launchAtLoginCaption: String
    let liquidGlassCaption: String
    let liquidGlassOtherWindows: String
    let panelIntro: String
    let panelReorderHint: String
    let menuBarIconTitle: String
    let menuBarIconCaption: String
    let menuBarIconOther: String
    let menuBarIconOtherCaption: String
    let menuBarIconUnknown: String
    let menuBarIconReset: String
    let iconMissingTitle: String
    let iconMissingCaption: String
    let sectionKeepAwake: String
    let sectionDisplays: String
    let sectionMixer: String
    let sectionSystem: String
    let sectionNetwork: String
    let sectionDisks: String
    let sectionPower: String
    let sectionUtilities: String
    let sectionControls: String
    let sectionToggles: String
}

extension FeatureStrings {
    static func generalSettings(_ language: AppLanguage) -> GeneralSettingsStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension GeneralSettingsStrings {

    static let enUS = GeneralSettingsStrings(
        pageDescription: "How Nyx starts, how it looks and what its menu bar panel shows.",
        appearanceCaption: "Applies to Nyx’s own windows and panels, not to the whole Mac.",
        launchAtLoginCaption: "Opens by itself every time you turn on your Mac.",
        liquidGlassCaption: "See-through, glass-like panels.",
        liquidGlassOtherWindows: "Other windows and panels",
        panelIntro: "Click Nyx’s icon in the menu bar to open the panel. Its tabs appear in this order.",
        panelReorderHint: "Drag to reorder. Switch off anything you don’t need.",
        menuBarIconTitle: "Menu bar icon",
        menuBarIconCaption: "Choose the icon Nyx shows in the menu bar.",
        menuBarIconOther: "Other symbol",
        menuBarIconOtherCaption: "Type the name of any SF Symbol. Leave it empty to use the Nyx icon.",
        menuBarIconUnknown: "This Mac has no symbol with that name.",
        menuBarIconReset: "Use the Nyx icon",
        iconMissingTitle: "Can’t find the icon?",
        iconMissingCaption: "A crowded menu bar can hide it, especially on Macs with a notch.",
        sectionKeepAwake: "Keeps your Mac awake for as long as you want.",
        sectionDisplays: "Brightness of your displays.",
        sectionMixer: "Volume of each app, one slider each.",
        sectionSystem: "Processor, graphics and memory at a glance.",
        sectionNetwork: "Internet speed and which apps are using it.",
        sectionDisks: "Free space and disk activity.",
        sectionPower: "Battery, charging and power use.",
        sectionUtilities: "Screenshots, cleaner, updates and other tools.",
        sectionControls: "Switches for mouse, keyboard and window features.",
        sectionToggles: "One-click actions like dark mode and muting the mic."
    )













}
