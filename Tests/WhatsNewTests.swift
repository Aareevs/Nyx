import Foundation

enum WhatsNewTests {
    static func run(_ suite: TestSuite) {
        func show(_ app: String, _ previous: String?, shown: String? = nil) -> Bool {
            WhatsNewInfo.shouldShow(appVersion: app, previousVersion: previous, shownVersion: shown)
        }
        suite.expect(show("1.1.0", "1.0.0"), "whats new: updating from 1.0.0 to 1.1.0 shows the window")
        suite.expect(show("1.1.0", "1.0.5"), "whats new: any older version shows it")
        suite.expect(!show("1.1.0", nil), "whats new: a fresh install goes through onboarding, not this window")
        suite.expect(!show("1.1.0", "1.1.0"), "whats new: relaunching the same version shows nothing")
        suite.expect(!show("1.1.0", "1.0.0", shown: "1.1.0"), "whats new: it is shown only once per version")
        suite.expect(show("1.1.0", "1.0.0", shown: "1.0.0"), "whats new: an older shown marker does not block a newer version")
        suite.expect(!show("1.0.0", "1.1.0"), "whats new: going back to an older version shows nothing")
        suite.expect(!show("1.1.1", "1.1.0"), "whats new: a version with nothing written for it stays quiet")
        suite.expect(!show("dev", "1.0.0"), "whats new: an unversioned build shows nothing")

        let items = WhatsNewInfo.items(for: "1.1.0")
        suite.expect(items.count >= 4 && items.count <= 8, "whats new: 1.1.0 lists a short set of changes")
        suite.expect(Set(items.map(\.title)).count == items.count, "whats new: every title is different")
        suite.expect(items.allSatisfy { !$0.symbol.isEmpty && !$0.title.isEmpty && !$0.text.isEmpty },
                     "whats new: every item has a symbol, a title and text")
        suite.expect(WhatsNewInfo.items(for: "9.9.9").isEmpty, "whats new: an unknown version has no items")
        suite.expect(WhatsNewInfo.releaseURL(for: "1.1.0").absoluteString == "https://github.com/Aareevs/Nyx/releases/tag/v1.1.0",
                     "whats new: See all changes opens that version's release page")
    }
}
