import Foundation

/// The in-app help, written like a small wiki: topics in a sidebar, one
/// article per topic. Every feature gets an article built from the same
/// title, description, permissions and shortcuts Settings shows, so the help
/// cannot drift from the app. A few hand-written guides sit on top.
struct HelpArticle: Identifiable, Hashable {
    struct Section: Hashable {
        let heading: String
        /// Paragraphs. `**bold**` is rendered as bold.
        let body: [String]
    }

    let id: String
    let title: String
    let symbol: String
    let summary: String
    let sections: [Section]
}

struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let articles: [HelpArticle]
}

@MainActor
enum HelpLibrary {
    static func topics() -> [HelpTopic] {
        [guides] + FeatureGroup.allCases.map(featureTopic)
    }

    static func articles() -> [HelpArticle] { topics().flatMap(\.articles) }

    /// Articles whose title, summary or text contains every word typed.
    static func search(_ query: String) -> [HelpArticle] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return articles().filter { article in
            let text = ([article.title, article.summary]
                + article.sections.flatMap { [$0.heading] + $0.body }).joined(separator: " ").lowercased()
            return words.allSatisfy(text.contains)
        }
    }

    // MARK: Features

    private static func featureTopic(_ group: FeatureGroup) -> HelpTopic {
        let hub = FeatureStrings.hub(L10n.shared.language)
        let title: String
        switch group {
        case .windowsDock: title = hub.groupWindowsDock
        case .mouseKeyboard: title = hub.groupMouseKeyboard
        case .clipboardFiles: title = hub.groupClipboardFiles
        case .sound: title = hub.groupSound
        case .energyDisplay: title = hub.groupEnergyDisplay
        case .tools: title = hub.groupTools
        case .dynamicIsland: title = FeatureStrings.notch(L10n.shared.language).title
        case .monitor: title = hub.groupMonitor
        }
        let features = AppFeature.allCases.filter { $0.group == group }
        return HelpTopic(id: group.rawValue, title: title, articles: features.map(article))
    }

    private static func article(for feature: AppFeature) -> HelpArticle {
        let s = L10n.shared.s
        let hub = FeatureStrings.hub(L10n.shared.language)
        var sections: [HelpArticle.Section] = [
            .init(heading: "What it does", body: [feature.hubDescription(hub)]),
        ]
        sections += extra[feature] ?? []

        let shortcuts = GlobalShortcutRole.allCases.filter { $0.feature == feature }
        if !shortcuts.isEmpty {
            sections.append(.init(heading: "Shortcuts", body: shortcuts.map {
                "**\($0.title(s))** \($0.defaultShortcut.displayString)"
            } + ["Change any of these in Settings → Shortcuts."]))
        }
        let permissions = feature.permissions
        if !permissions.isEmpty {
            sections.append(.init(heading: "Permissions", body: permissions.map {
                "**\($0.name(hub))**: \($0.explainer(hub))"
            }))
        } else {
            sections.append(.init(heading: "Permissions", body: ["This tool needs no special permission."]))
        }
        sections.append(.init(heading: "Turning it on", body: [
            "Switch it on in Settings → Features. It stays off until you do.",
        ]))
        let title = feature.hubTitle(s, hub: hub)
        return HelpArticle(id: feature.rawValue, title: title, symbol: feature.symbolName,
                           summary: feature.hubDescription(hub), sections: sections)
    }

    /// Extra detail on top of the generated sections, for features that
    /// need more than a description.
    private static let extra: [AppFeature: [HelpArticle.Section]] = [
        .mixer: [.init(heading: "Which apps show up", body: [
            "An app appears once it has an audio connection, usually when it starts playing or preparing sound. An app that is open but silent can be missing.",
            "Nyx remembers each app's volume and output, so they come back next time.",
        ])],
        .notchStreaks: [.init(heading: "How each streak works", body: [
            "**GitHub and LeetCode:** enter your username once. Nyx reads your public activity and shows the current streak.",
            "**Reddit:** Reddit can't be read automatically, so you mark the day done yourself with **Done**.",
            "The island's border pulses in the service's colour when a streak goes up.",
        ])],
        .notch: [.init(heading: "Home", body: [
            "The first page shows **sliders** for volume, brightness and keyboard light, **now playing** with play, skip and a seek bar, **today's events** from the calendars you chose, and a row of **shortcuts** you pick yourself.",
            "Settings → Dynamic Island → Pages lets you turn pages on or off and drag them into order.",
        ])],
    ]

    // MARK: Guides

    private static let guides = HelpTopic(id: "guides", title: "Getting started", articles: [
        HelpArticle(
            id: "welcome", title: "Welcome to Nyx", symbol: "sparkles",
            summary: "Nyx is a menu-bar and Dynamic Island utility for your Mac. Every tool is optional.",
            sections: [
                .init(heading: "How Nyx is laid out", body: [
                    "Nyx lives in the **menu bar** and, around the camera housing, in the **Dynamic Island**.",
                    "**Settings** is where you turn tools on and change how they behave. Nothing runs until you enable it.",
                ]),
                .init(heading: "Finding things", body: [
                    "Use the search field at the top of the Settings sidebar. It finds tools, options and shortcuts by name.",
                    "This help lists every feature, grouped the way Settings groups them.",
                ]),
            ]),
        HelpArticle(
            id: "permissions", title: "Permissions", symbol: "lock.shield",
            summary: "Some tools need macOS to allow them first. Nyx only asks when you turn one of those tools on.",
            sections: [
                .init(heading: "Why Nyx asks", body: [
                    "Window tools, shortcuts and the volume keys need **Accessibility**. Screen tools need **Screen Recording**.",
                    "Each feature's article lists exactly what it needs.",
                ]),
            ]),
    ])
}
