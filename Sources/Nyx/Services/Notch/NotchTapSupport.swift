import Foundation

enum NotchTapSupport {
    static let defaultsKey = DefaultsKey.notchTapToOpen
    /// Sentient OS's standard tuning.
    static let sensitivity = 1.1

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }
}
