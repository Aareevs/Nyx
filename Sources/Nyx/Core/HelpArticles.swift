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
            "**Reddit:** reddit.com doesn't allow apps to read your streak, so Nyx can't see it. You mark each day done yourself with **Mark done**, and Nyx counts the days you mark.",
            "The island's border pulses in the service's colour when a streak goes up.",
        ])],
        .notchChat: [
            .init(heading: "Getting started", body: [
                "Open **Settings → Chat** to add a key and set Chat up. Then open it from the Chat button beside the island, or turn on its shortcut there (Option+Shift+Space by default).",
                "Pick **Claude, OpenAI, Gemini or NVIDIA**, paste an API key from that service (or the whole code snippet it comes in) and press **Connect**. The key is checked once, then kept in a private file on your Mac that only your account can read.",
                "Chat opens in the Dynamic Island, so the island has to be on.",
            ]),
            .init(heading: "Ask about selected text", body: [
                "Select text in any app and press the shortcut. The text is attached above the field so you can see it. It is sent only when you send your message.",
                "This works where the app shares its selection and Accessibility is already allowed for Nyx. Chat never asks for Accessibility itself. The clipboard button next to the field attaches what you copied instead.",
            ]),
            .init(heading: "Your chats and your key", body: [
                "Messages go straight from your Mac to the service you chose. Nyx has no server in between, and keys never appear in backups.",
                "Chats are saved as plain text on your Mac, 50 by default. Turn saving off or delete them all in Settings → Chat.",
                "Using a service costs whatever that service charges for your key.",
            ]),
            .init(heading: "What you can set", body: [
                "In **Settings → Chat** (under Utilities): your keys for each service and which model to use, instructions sent at the start of every chat, how big the chat page is, whether chats are kept and how many, whether the selected text is attached, and the shortcut.",
                "Each service keeps its own chats. Switching service starts a new chat, and the history panel shows only the chats of the service in use.",
            ]),
            .init(heading: "Option+Shift+Space", body: [
                "Chat's shortcut is Option+Shift+Space, next to the Command Bar's Option+Space, so the two never clash. You can change it in **Settings → Chat**. If another app already uses the combination, Nyx tells you and you can pick a different one.",
            ]),
        ],
        .notch: [
            .init(heading: "Home", body: [
                "The first page shows **sliders** for volume, brightness and keyboard light, **now playing** with play, skip and a seek bar, **today's events** from the calendars you chose, and a row of **shortcuts** you pick yourself.",
                "Settings → Dynamic Island → Pages lets you turn pages on or off and drag them into order.",
            ]),
            .init(heading: "Playlists: Spotify and YouTube", body: [
                "On the Music page, press the **Playlists** button and pick **Spotify** or **YouTube** at the top. Spotify needs you to connect once, and Premium to play.",
                "For YouTube and YouTube Music, press **+** (or **Paste link**) and add a playlist link. Public and unlisted playlists work, private ones can't be read. Your list is saved only on this Mac.",
                "Tap a song and it plays inside Nyx, with no browser. It shows in the island's player, so play, pause, next, previous and the seek bar work as usual. The arrows button reorders or removes playlists.",
                "YouTube's ads play unless you sign in: the person icon next to the **+** has an optional **Sign in to YouTube**, so YouTube Premium applies. The login stays in Nyx's own storage, and you can sign out there.",
            ]),
        ],
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
