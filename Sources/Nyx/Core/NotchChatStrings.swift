import Foundation

struct NotchChatStrings {
    let title: String
    let description: String
    // The page
    let setupTitle: String
    let setupHint: String
    let keyPlaceholder: String
    let connect: String
    let paste: String
    let cancel: String
    let changeKey: String
    let removeKey: String
    let connecting: String
    let keyLooksWrong: String
    let snippetNoKey: String
    let placeholder: String
    let send: String
    let stop: String
    let newChat: String
    let history: String
    let noHistory: String
    let chatsOf: String
    let today: String
    let yesterday: String
    let previousWeek: String
    let previousMonth: String
    let older: String
    let model: String
    let otherModel: String
    let refreshModels: String
    let provider: String
    let copy: String
    let copied: String
    let selectedText: String
    let addClipboard: String
    let removeAttachment: String
    let addFile: String
    let readingFile: String
    let cutShort: String
    let emptyTitle: String
    let emptyHint: String
    let interrupted: String
    let retry: String
    let deleteChat: String
    // Failures
    let noKey: String
    let rejected: String
    let rateLimited: String
    let unreachable: String
    let emptyReply: String
    let apiError: String
    // Settings
    let keysTitle: String
    let keysHint: String
    let keySaved: String
    let keyNone: String
    let save: String
    let remove: String
    let replace: String
    let systemPrompt: String
    let systemPromptHint: String
    let systemPromptPlaceholder: String
    let saveHistory: String
    let saveHistoryHint: String
    let historyLimit: String
    let clearHistory: String
    let clearHistoryConfirm: String
    let sizeTitle: String
    let sizeRegular: String
    let sizeLarge: String
    let sizeHuge: String
    let sizeHint: String
    let enable: String
    let openSettings: String
    let useSelection: String
    let useSelectionHint: String
    let shortcut: String
    let shortcutHint: String
    let needsIsland: String
    let privacy: String

    func title(of bucket: ChatHistoryRules.Bucket) -> String {
        switch bucket {
        case .today: return today
        case .yesterday: return yesterday
        case .week: return previousWeek
        case .month: return previousMonth
        case .older: return older
        }
    }

    func failure(_ failure: ChatFailure, provider: ChatProvider) -> String {
        switch failure {
        case .noKey: return noKey
        case .rejected: return String(format: rejected, provider.displayName)
        case .rateLimited: return String(format: rateLimited, provider.displayName)
        case .unreachable: return unreachable
        case .emptyReply: return emptyReply
        case .api(let message): return String(format: apiError, provider.displayName, message)
        }
    }
}

extension FeatureStrings {
    static func notchChat(_ language: AppLanguage) -> NotchChatStrings {
        switch language {
        case .enUS: return NotchChatStrings(
            title: "Chat",
            description: "Chat with Claude, OpenAI, Gemini or NVIDIA from the Dynamic Island, using your own API key. Open it from its button beside the island or with a shortcut, and ask about whatever text you have selected.",
            setupTitle: "Chat with an AI of your choice",
            setupHint: "Add an API key from Claude, OpenAI, Gemini or NVIDIA, or paste the code snippet it comes in. It is kept in a private file on this Mac and only ever sent to that service.",
            keyPlaceholder: "Paste your API key",
            connect: "Connect",
            paste: "Paste",
            cancel: "Cancel",
            changeKey: "Change API key…",
            removeKey: "Remove this key",
            connecting: "Checking…",
            keyLooksWrong: "That does not look like an API key.",
            snippetNoKey: "That snippet has no key in it. Create a key on the service’s site, then copy the snippet again.",
            placeholder: "Ask anything",
            send: "Send",
            stop: "Stop",
            newChat: "New chat",
            history: "Chats",
            noHistory: "No saved chats",
            chatsOf: "%@ chats",
            today: "Today",
            yesterday: "Yesterday",
            previousWeek: "Previous 7 days",
            previousMonth: "Previous 30 days",
            older: "Older",
            model: "Model",
            otherModel: "Other model…",
            refreshModels: "Refresh the model list",
            provider: "Service",
            copy: "Copy",
            copied: "Copied",
            selectedText: "Selected text",
            addClipboard: "Add what is on the clipboard",
            removeAttachment: "Remove",
            addFile: "Add a file: pictures, PDF, Word, Excel, CSV or text",
            readingFile: "Reading the file…",
            cutShort: "cut short",
            emptyTitle: "Ask anything",
            emptyHint: "Select text in any app and press the shortcut to ask about it.",
            interrupted: "Stopped",
            retry: "Try again",
            deleteChat: "Delete chat",
            noKey: "Add an API key for this service first.",
            rejected: "%@ did not accept the key. Check that it is right and still active.",
            rateLimited: "%@ says the limit or quota is used up. Try again in a moment.",
            unreachable: "Could not reach the service. Check the connection.",
            emptyReply: "The reply came back empty.",
            apiError: "%@: %@",
            keysTitle: "API keys",
            keysHint: "Each key stays in a private file on this Mac that only your account can read, is sent only to its own service, and never appears in a backup.",
            keySaved: "Key saved",
            keyNone: "No key",
            save: "Save",
            remove: "Remove",
            replace: "Replace",
            systemPrompt: "Instructions",
            systemPromptHint: "Sent first in every chat, for how you want it to answer.",
            systemPromptPlaceholder: "For example: answer briefly, in plain words.",
            saveHistory: "Keep chats",
            saveHistoryHint: "Chats are stored as plain text on this Mac. With this off, they are gone when you quit Nyx.",
            historyLimit: "Chats to keep",
            clearHistory: "Delete all chats",
            clearHistoryConfirm: "Delete every saved chat? This cannot be undone.",
            sizeTitle: "Chat size",
            sizeRegular: "Regular",
            sizeLarge: "Large",
            sizeHuge: "Huge",
            sizeHint: "How big the chat page is when it opens. It is larger than the island’s other pages, whatever size you chose for them, and never larger than your screen.",
            enable: "Show the Chat page in the Dynamic Island",
            openSettings: "Open Chat settings",
            useSelection: "Ask about the selected text",
            useSelectionHint: "Opening chat with its shortcut attaches the text you have selected, where the app shares it. You see it before anything is sent.",
            shortcut: "Open chat",
            shortcutHint: "Works from any app while the Dynamic Island is on.",
            needsIsland: "Chat opens in the Dynamic Island. Turn the island on to use it.",
            privacy: "Messages go straight from this Mac to the service you pick. Nyx has no server in between.")
        }
    }
}
