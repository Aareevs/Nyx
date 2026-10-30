struct MixerScreenSharingStrings {
    let allowVolumeControl: String
    let protectedCaption: String
    let sharingWarning: String

    static func localized(_ language: AppLanguage) -> MixerScreenSharingStrings {
        switch language {
        case .enUS: return .init(
            allowVolumeControl: "Allow volume control",
            protectedCaption: "Volume control is off to prevent echo when sharing audio.",
            sharingWarning: "Turn off volume control before sharing audio to avoid echo.")
        }
    }
}
