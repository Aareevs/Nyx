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

    private func matches(_ title: String) -> Bool {
        let patterns: [String]
        switch self {
        case .instagram: patterns = [#"(?i)\binstagram\b"#]
        case .reddit: patterns = [#"(?i)\breddit\b"#, #"(?i)\br/\w+"#]
        case .x: patterns = [#" / X$"#, #" on X: "#, #"\(\d+\) .* / X$"#]
        }
        return patterns.contains { title.range(of: $0, options: .regularExpression) != nil }
    }

    var imageData: Data? {
        Bundle.main.url(forResource: "site-\(rawValue)", withExtension: "png", subdirectory: "Images")
            .flatMap { try? Data(contentsOf: $0) }
    }
}
