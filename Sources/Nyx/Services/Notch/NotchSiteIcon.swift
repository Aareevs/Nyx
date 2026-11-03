import AppKit
import Foundation

/// A browser sends the page's own icon as the cover, or for a private window
/// its incognito glyph, so a tab on Instagram, Reddit, X, Netflix, Hotstar or LinkedIn would not show
/// where it plays. Their tab titles name them, so the cover is replaced by
/// the site's logo, which ships in Resources/Images.
enum NotchSiteIcon: String, CaseIterable {
    case instagram, reddit, x, netflix, hotstar, linkedin

    private static let browsers: Set<String> = [
        "com.microsoft.edgemac", "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "company.thebrowser.Browser", "com.apple.Safari",
        "org.chromium.Chromium"
    ]

    static func site(forTitle title: String?, bundle: String?) -> NotchSiteIcon? {
        guard let title, let bundle, browsers.contains(bundle) else { return nil }
        return allCases.first { $0.matches(title) }
    }

    /// Some pages report a title that names no site ("Ro-Ko Relive Glory Days"
    /// on JioHotstar, a tweet's own text on X), so the title cannot say where
    /// it plays. The browser can: the tab whose title is the playing title
    /// has an address. That also finds a tab in the background. The first
    /// lookup asks macOS for Automation access to the browser, and each
    /// title is asked about once.
    /// The icon for what a browser is playing. The tab's address decides when
    /// macOS lets Nyx read it, so a video that merely mentions a site in its
    /// title ("How to use LinkedIn" on YouTube) keeps its own cover. Without
    /// that access, or when no tab matches, the title alone is read, as it
    /// always was. Nothing here asks for access: the Allow button does.
    static func site(playing title: String?, bundle: String?) -> NotchSiteIcon? {
        let byTitle = site(forTitle: title, bundle: bundle)
        guard let title, let bundle, let app = scriptable[bundle],
              automationStatus(bundle: bundle, ask: false) == noErr else { return byTitle }
        let wanted = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard wanted.count >= 4 else { return byTitle }
        let key = bundle + "\u{1}" + wanted
        let now = Date()
        let tab: TabLookup
        if let hit = cacheLock.withLock({ cache[key] }), now.timeIntervalSince(hit.at) < 20 {
            tab = hit.result
        } else {
            tab = tabLookup(app: app.name, usesName: app.usesName, wanted: wanted)
            cacheLock.withLock {
                if cache.count > 40 { cache.removeAll() }
                cache[key] = (tab, now)
            }
        }
        switch tab {
        case .site(let site): return site
        case .elsewhere: return nil
        case .notFound: return byTitle
        }
    }

    private enum TabLookup: Equatable { case site(NotchSiteIcon), elsewhere, notFound }

    /// A running browser Nyx can ask about its tabs, and whether macOS lets it.
    struct BrowserAccess: Identifiable, Equatable {
        let bundle: String
        let name: String
        var allowed: Bool
        var id: String { bundle }
    }

    /// Browsers that are open now, with the Automation answer macOS holds for
    /// each. Asking never shows a prompt.
    static func browserAccess() -> [BrowserAccess] {
        scriptable.compactMap { bundle, app in
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { return nil }
            return BrowserAccess(bundle: bundle, name: app.name, allowed: automationStatus(bundle: bundle, ask: false) == noErr)
        }.sorted { $0.name < $1.name }
    }

    /// Asks each open browser for access, which makes macOS show its own
    /// prompt for any that has not been answered yet.
    static func requestBrowserAccess() {
        for bundle in scriptable.keys where !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty {
            _ = automationStatus(bundle: bundle, ask: true)
        }
        cacheLock.withLock { cache.removeAll() }
    }

    private static func automationStatus(bundle: String, ask: Bool) -> OSStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundle)
        guard let target = descriptor.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, ask)
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (result: TabLookup, at: Date)] = [:]

    private static let scriptable: [String: (name: String, usesName: Bool)] = [
        "com.microsoft.edgemac": ("Microsoft Edge", false), "com.google.Chrome": ("Google Chrome", false),
        "com.brave.Browser": ("Brave Browser", false), "com.vivaldi.Vivaldi": ("Vivaldi", false),
        "company.thebrowser.Browser": ("Arc", false), "com.apple.Safari": ("Safari", true)
    ]

    private static let hosts: [(String, NotchSiteIcon)] = [
        ("hotstar.com", .hotstar), ("netflix.com", .netflix), ("instagram.com", .instagram),
        ("reddit.com", .reddit), ("linkedin.com", .linkedin), ("x.com", .x), ("twitter.com", .x)
    ]

    private static func tabLookup(app: String, usesName: Bool, wanted: String) -> TabLookup {
        let script = """
        tell application "\(app)"
            set rows to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set rows to rows & (URL of t) & "\\t" & (\(usesName ? "name" : "title") of t) & "\\n"
                end repeat
            end repeat
            return rows
        end tell
        """
        guard let output = NSAppleScript(source: script)?.executeAndReturnError(nil).stringValue else { return .notFound }
        var elsewhere = false
        for row in output.split(separator: "\n") {
            let fields = row.split(separator: "\t", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { continue }
            let tab = fields[1].lowercased()
            guard tab.contains(wanted) || (tab.count >= 4 && wanted.contains(tab)),
                  let host = URL(string: fields[0])?.host?.lowercased() else { continue }
            if let match = hosts.first(where: { host == $0.0 || host.hasSuffix("." + $0.0) }) { return .site(match.1) }
            elsewhere = true
        }
        return elsewhere ? .elsewhere : .notFound
    }

    private func matches(_ title: String) -> Bool {
        let patterns: [String]
        switch self {
        case .instagram: patterns = [#"(?i)\binstagram\b"#]
        case .reddit: patterns = [#"(?i)\breddit\b"#, #"(?i)\br/\w+"#]
        case .netflix: patterns = [#"(?i)\bnetflix\b"#]
        case .hotstar: patterns = [#"(?i)\b(?:jio|disney\+? ?)?hotstar\b"#]
        case .linkedin: patterns = [#"(?i)\blinkedin\b"#]
        case .x: patterns = [#" / X(?: - .*)?$"#, #" on X: "#]
        }
        return patterns.contains { title.range(of: $0, options: .regularExpression) != nil }
    }

    var imageData: Data? {
        Bundle.main.url(forResource: "site-\(rawValue)", withExtension: "png", subdirectory: "Images")
            .flatMap { try? Data(contentsOf: $0) }
    }
}
