import AppKit
import ApplicationServices
import Foundation

/// A browser sends the page's own icon as the cover, or for a private window
/// its incognito glyph, so a tab on Instagram, Reddit or X would not show
/// where it plays. Their tab titles name them, so the cover is replaced by
/// the site's logo, which ships in Resources/Images.
enum NotchSiteIcon: String, CaseIterable {
    case instagram, reddit, x

    private static let browsers: Set<String> = [
        "com.microsoft.edgemac", "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "company.thebrowser.Browser", "com.apple.Safari",
        "org.chromium.Chromium"
    ]

    static func site(forTitle title: String?, bundle: String?) -> NotchSiteIcon? {
        guard let title, let bundle, browsers.contains(bundle) else { return nil }
        return allCases.first { $0.matches(title) }
    }

    /// A feed or a video often reports only the post's text as its title
    /// ("i think we have a clear winner here"), which names no site. The
    /// browser's front window does: "Home / X - Personal - Microsoft Edge".
    /// Read through Accessibility, which Nyx already holds for its shortcuts.
    /// Only the front window counts, since a tab in the background cannot be
    /// told apart from the one that is playing.
    static func site(forFrontWindowOf bundle: String?) -> NotchSiteIcon? {
        guard let bundle, browsers.contains(bundle), AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
              app.isActive else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window = window else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String else { return nil }
        return allCases.first { $0.matches(text) }
    }

    private func matches(_ title: String) -> Bool {
        let patterns: [String]
        switch self {
        case .instagram: patterns = [#"(?i)\binstagram\b"#]
        case .reddit: patterns = [#"(?i)\breddit\b"#, #"(?i)\br/\w+"#]
        case .x: patterns = [#" / X(?: - .*)?$"#, #" on X: "#]
        }
        return patterns.contains { title.range(of: $0, options: .regularExpression) != nil }
    }

    var imageData: Data? {
        Bundle.main.url(forResource: "site-\(rawValue)", withExtension: "png", subdirectory: "Images")
            .flatMap { try? Data(contentsOf: $0) }
    }
}
