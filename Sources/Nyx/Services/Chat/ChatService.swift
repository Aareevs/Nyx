import AppKit
import Combine
import Foundation

/// Text the person adds to their next message: what they had selected when
/// chat opened, or what is on the clipboard. It is shown, and sent only with a
/// message.
struct ChatAttachment: Equatable {
    var text: String
    var fromClipboard: Bool
}

/// The chat behind the island's page: the keys, the models, the streaming
/// replies and the saved chats. One conversation is open at a time.
@MainActor
final class ChatService: ObservableObject {
    static let shared = ChatService()

    /// The longest attachment sent. A page of prose, not a book.
    static let maximumAttachment = 12_000

    @Published private(set) var conversations: [ChatConversation] = []
    @Published private(set) var currentID: UUID?
    @Published private(set) var isStreaming = false
    @Published private(set) var failure: ChatFailure?
    @Published private(set) var models: [ChatProvider: [ChatModel]] = [:]
    @Published private(set) var loadingModels: Set<ChatProvider> = []
    @Published private(set) var keyed: Set<ChatProvider> = []
    @Published private(set) var checkingKey = false
    @Published var draft = ""
    @Published var attachment: ChatAttachment?
    @Published private(set) var files: [ChatPendingFile] = []
    @Published private(set) var readingFiles = false
    @Published private(set) var fileProblem: String?
    /// Bumped each time chat is opened with the shortcut, so the field can take
    /// the keyboard again even when the page was already showing.
    @Published private(set) var focusSerial = 0

    private let defaults: UserDefaults
    private let keyStore: ChatKeyStore
    private let history: ChatHistoryStore
    private let session: URLSession
    private let hotkey = QuickToolHotkey(id: 82)
    private var streamTask: Task<Void, Never>?
    private var modelTasks: [ChatProvider: Task<Void, Never>] = [:]
    private var observer: AnyCancellable?
    private var loaded = false

    private(set) var shortcutRegistrationFailed = false

    init(defaults: UserDefaults = .standard,
         keyStore: ChatKeyStore = ChatFileKeyStore(
            directoryURL: PrivateFileStore.containerURL?.appendingPathComponent("Chat", isDirectory: true)),
         history: ChatHistoryStore = ChatHistoryStore(
            directoryURL: PrivateFileStore.containerURL?.appendingPathComponent("Chat", isDirectory: true)),
         session: URLSession? = nil) {
        self.defaults = defaults
        self.keyStore = keyStore
        self.history = history
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: configuration)
        hotkey.onPress = { [weak self] in self?.shortcutPressed() }
    }

    // MARK: Lifecycle

    /// The hotkey follows the feature, the island and the person's switch, and
    /// any preference change re-checks it.
    func syncWithPreferences() {
        if observer == nil {
            observer = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in self?.syncShortcut() }
        }
        refreshKeys()
        syncShortcut()
    }

    private func syncShortcut() {
        let wanted = AppFeature.notchChat.isAvailable && NotchSupport.isEnabled()
            && defaults.bool(forKey: DefaultsKey.notchChatEnabled)
            && defaults.bool(forKey: DefaultsKey.notchChatShortcutEnabled)
            && !ShortcutCapture.isCapturing
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.notchChatShortcut, fallback: .chatDefault)
        let failed = !hotkey.sync(enabled: wanted, shortcut: shortcut, storageKey: DefaultsKey.notchChatShortcut)
        if failed != shortcutRegistrationFailed { shortcutRegistrationFailed = failed; objectWillChange.send() }
    }

    func stop() {
        cancelStreaming()
        hotkey.unregister()
    }

    /// Called when the page appears: reads saved chats once, and the keys.
    func prepare() {
        refreshKeys()
        guard !loaded else { return }
        loaded = true
        if defaults.bool(forKey: DefaultsKey.notchChatSaveHistory) {
            conversations = ChatHistoryRules.trimmed(history.load(), limit: historyLimit)
        }
    }

    // MARK: Shortcut

    private func shortcutPressed() {
        guard AppFeature.notchChat.isAvailable, NotchSupport.routesChat() else { return }
        let notch = NotchService.shared
        if notch.isShowingChat { notch.collapse(); return }
        guard defaults.bool(forKey: DefaultsKey.notchChatUseSelection) else { openPage(); return }
        // The selection is read before the island takes the keyboard, from the
        // app that has it. Nothing is asked for: without Accessibility the read
        // is simply empty.
        Task {
            let selection = await Task.detached(priority: .userInitiated) {
                CommandBarSelectionReader.readSelection()
            }.value
            if !selection.text.isEmpty {
                attachment = ChatAttachment(text: String(selection.text.prefix(Self.maximumAttachment)),
                                            fromClipboard: false)
            }
            openPage()
        }
    }

    private func openPage() {
        focusSerial &+= 1
        NotchService.shared.openChat()
    }

    // MARK: Keys

    var provider: ChatProvider {
        get {
            let stored = ChatProvider(rawValue: defaults.string(forKey: DefaultsKey.notchChatProvider) ?? "") ?? .claude
            // The one last used may have no key any more; chat then opens on one that has.
            if !keyed.isEmpty, !keyed.contains(stored), let other = ChatProvider.allCases.first(where: keyed.contains) { return other }
            return stored
        }
        set {
            guard newValue != provider else { return }
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: DefaultsKey.notchChatProvider)
            // Each service keeps its own chats: a chat of another one is not carried over.
            if let chat = current, chat.provider != newValue {
                cancelStreaming()
                currentID = nil
                failure = nil
                draft = ""
            }
        }
    }

    var hasKey: Bool { keyed.contains(provider) }

    func hasKey(for provider: ChatProvider) -> Bool { keyed.contains(provider) }

    private func refreshKeys() {
        let present = Set(ChatProvider.allCases.filter { keyStore.key(for: $0) != nil })
        if present != keyed { keyed = present }
    }

    /// Saves the key after one request that proves the service takes it. A
    /// rejected key is not kept. The service's own answer decides, so a key
    /// for a model list the account cannot read still counts when the
    /// service did not say the key was wrong.
    func connect(_ provider: ChatProvider, key: String, completion: @escaping (ChatFailure?) -> Void) {
        // The key itself, or one pasted inside a code snippet.
        guard let key = ChatProvider.extractKey(from: key) else { completion(.rejected); return }
        checkingKey = true
        Task { [session] in
            let outcome = await ChatTransport.availableModels(provider: provider, key: key, session: session)
            self.checkingKey = false
            switch outcome {
            case .success(let list):
                self.keyStore.setKey(key, for: provider)
                self.refreshKeys()
                self.models[provider] = list
                self.adoptModel(for: provider, from: list)
                self.provider = provider
                self.failure = nil
                completion(nil)
            case .failure(let reason):
                // Only a refusal of the key keeps it out; a network problem
                // says nothing about the key.
                if reason == .rejected { completion(.rejected) }
                else if reason == .unreachable { completion(.unreachable) }
                // A key that no model would answer for is not kept: the reason is the answer.
                else if provider == .nvidia { completion(reason) }
                else {
                    self.keyStore.setKey(key, for: provider)
                    self.refreshKeys()
                    self.provider = provider
                    completion(nil)
                }
            }
        }
    }

    func removeKey(for provider: ChatProvider) {
        keyStore.setKey(nil, for: provider)
        models[provider] = nil
        refreshKeys()
        if self.provider == provider, let other = ChatProvider.allCases.first(where: { keyed.contains($0) }) {
            self.provider = other
        }
    }

    // MARK: Models

    func model(for provider: ChatProvider) -> String {
        let stored = defaults.string(forKey: DefaultsKey.notchChatModel(provider.rawValue)) ?? ""
        return stored.isEmpty ? provider.fallbackModel : stored
    }

    func setModel(_ id: String, for provider: ChatProvider) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        objectWillChange.send()
        defaults.set(trimmed, forKey: DefaultsKey.notchChatModel(provider.rawValue))
    }

    /// A model nobody picked yet starts on the service's mainstream one; one the
    /// person chose stays, unless the service no longer lists it.
    private func adoptModel(for provider: ChatProvider, from list: [ChatModel]) {
        guard !list.isEmpty else { return }
        let stored = defaults.string(forKey: DefaultsKey.notchChatModel(provider.rawValue)) ?? ""
        if stored.isEmpty || !list.contains(where: { $0.id == stored }) {
            setModel(ChatAPI.defaultModel(in: list, provider: provider), for: provider)
        }
    }

    func refreshModels(for provider: ChatProvider) {
        guard let key = keyStore.key(for: provider), modelTasks[provider] == nil else { return }
        loadingModels.insert(provider)
        modelTasks[provider] = Task { [session] in
            let outcome = await ChatTransport.availableModels(provider: provider, key: key, session: session)
            self.modelTasks[provider] = nil
            self.loadingModels.remove(provider)
            if case .success(let list) = outcome {
                self.models[provider] = list
                self.adoptModel(for: provider, from: list)
            }
        }
    }

    // MARK: Conversations

    var current: ChatConversation? {
        guard let currentID else { return nil }
        return conversations.first { $0.id == currentID }
    }

    var messages: [ChatMessage] { current?.messages ?? [] }

    /// The chats of the service in use, newest first.
    var providerConversations: [ChatConversation] {
        conversations.filter { $0.provider == provider }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var saves: Bool { defaults.bool(forKey: DefaultsKey.notchChatSaveHistory) }

    var historyLimit: Int {
        ChatHistoryRules.clampedLimit(defaults.integer(forKey: DefaultsKey.notchChatHistoryLimit))
    }

    var systemPrompt: String { defaults.string(forKey: DefaultsKey.notchChatSystemPrompt) ?? "" }

    func newChat() {
        cancelStreaming()
        currentID = nil
        failure = nil
        draft = ""
    }

    func open(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        cancelStreaming()
        currentID = id
        failure = nil
        if let chat = current { provider = chat.provider }
    }

    func delete(_ id: UUID) {
        if currentID == id { cancelStreaming(); currentID = nil }
        conversations.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        cancelStreaming()
        currentID = nil
        conversations = []
        history.deleteAll()
    }

    /// Called when the history switch or limit changes.
    func historySettingsChanged() {
        if saves {
            conversations = ChatHistoryRules.trimmed(conversations, limit: historyLimit)
            persist()
        } else {
            history.deleteAll()
        }
    }

    private func persist() {
        guard saves else { return }
        conversations = ChatHistoryRules.trimmed(conversations, limit: historyLimit)
        history.save(conversations)
    }

    private func index(of id: UUID) -> Int? { conversations.firstIndex { $0.id == id } }

    // MARK: Attachments

    func attachClipboard() {
        GeneralPasteboardAccess.shared.async({ NSPasteboard.general.string(forType: .string) }) { [weak self] text in
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let self, !trimmed.isEmpty else { return }
            self.attachment = ChatAttachment(text: String(trimmed.prefix(Self.maximumAttachment)), fromClipboard: true)
        }
    }

    func attachFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        readingFiles = true
        fileProblem = nil
        Task {
            var problems: [String] = []
            for url in urls {
                let result = await Task.detached { ChatFileReader.read(url) }.value
                switch result {
                case .success(let file):
                    let pictures = files.reduce(0) { $0 + $1.images.count }
                    if pictures + file.images.count > ChatFileReader.maximumImages {
                        problems.append("Up to \(ChatFileReader.maximumImages) pictures per message.")
                    } else {
                        files.append(file)
                    }
                case .failure(let error): problems.append(error.message)
                }
            }
            readingFiles = false
            fileProblem = problems.first
        }
    }

    func removeFile(_ file: ChatPendingFile) {
        files.removeAll { $0.id == file.id }
        fileProblem = nil
    }

    // MARK: Sending

    var canSend: Bool {
        !isStreaming && !readingFiles
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty)
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !files.isEmpty, !isStreaming, !readingFiles else { return }
        guard let key = keyStore.key(for: provider) else { failure = .noKey; return }
        let provider = provider
        let model = model(for: provider)

        var message = ChatMessage(role: .user, text: text.isEmpty ? "What is in the attached file?" : text)
        message.context = attachment?.text
        message.files = files.map { ChatFileInfo(name: $0.name, symbol: $0.symbol, imageCount: $0.images.count) }
        message.fileText = ChatMessage.fileBlock(files)
        message.images = files.flatMap(\.images)
        let reply = ChatMessage(role: .assistant, text: "")

        let id: UUID
        if let current {
            id = current.id
            if let position = index(of: id) {
                conversations[position].messages += [message, reply]
                conversations[position].provider = provider
                conversations[position].model = model
                conversations[position].updatedAt = Date()
            }
        } else {
            let chat = ChatConversation(title: ChatConversation.title(from: message.text), provider: provider, model: model,
                                        createdAt: Date(), updatedAt: Date(), messages: [message, reply])
            conversations.insert(chat, at: 0)
            currentID = chat.id
            id = chat.id
        }
        draft = ""
        attachment = nil
        files = []
        fileProblem = nil
        failure = nil
        startStream(conversationID: id, replyID: reply.id, provider: provider, model: model, key: key)
    }

    /// Asks again for the last reply, when it failed (the message stands with
    /// no reply) or was stopped (the reply stands unfinished).
    func retry() {
        guard !isStreaming, let current, let position = index(of: current.id),
              let last = conversations[position].messages.last else { return }
        guard let key = keyStore.key(for: provider) else { failure = .noKey; return }
        let provider = provider
        let model = model(for: provider)
        let replyID: UUID
        if last.role == .assistant {
            replyID = last.id
            conversations[position].messages[conversations[position].messages.count - 1] =
                ChatMessage(id: last.id, role: .assistant, text: "")
        } else {
            let reply = ChatMessage(role: .assistant, text: "")
            conversations[position].messages.append(reply)
            replyID = reply.id
        }
        conversations[position].provider = provider
        conversations[position].model = model
        failure = nil
        startStream(conversationID: current.id, replyID: replyID, provider: provider, model: model, key: key)
    }

    /// Whether the last turn has no complete reply, so a retry means something.
    var canRetry: Bool {
        guard !isStreaming, let last = messages.last else { return false }
        return last.role == .user || last.interrupted
    }

    func stopStreaming() {
        streamTask?.cancel()
    }

    private func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    private func startStream(conversationID: UUID, replyID: UUID, provider: ChatProvider, model: String, key: String) {
        guard let position = index(of: conversationID) else { return }
        let sent = conversations[position].messages.filter { $0.id != replyID }
        let request = ChatAPI.chatRequest(provider: provider, model: model, apiKey: key,
                                          system: systemPrompt, messages: sent)
        isStreaming = true
        streamTask = Task { [session] in
            await self.stream(request, provider: provider, session: session, conversationID: conversationID, replyID: replyID)
        }
    }

    private func append(_ text: String, to replyID: UUID, in conversationID: UUID) {
        guard let position = index(of: conversationID),
              let message = conversations[position].messages.lastIndex(where: { $0.id == replyID }) else { return }
        conversations[position].messages[message].text += text
    }

    private func finish(conversationID: UUID, replyID: UUID, failure: ChatFailure?, stopped: Bool) {
        isStreaming = false
        streamTask = nil
        guard let position = index(of: conversationID),
              let message = conversations[position].messages.lastIndex(where: { $0.id == replyID }) else { return }
        let empty = conversations[position].messages[message].text.isEmpty
        if let failure {
            self.failure = failure
            if empty { conversations[position].messages.remove(at: message) }
            else { conversations[position].messages[message].interrupted = true }
        } else if stopped {
            if empty { conversations[position].messages.remove(at: message) }
            else { conversations[position].messages[message].interrupted = true }
        } else if empty {
            self.failure = .emptyReply
            conversations[position].messages.remove(at: message)
        }
        conversations[position].updatedAt = Date()
        persist()
    }

    private func stream(_ request: URLRequest, provider: ChatProvider, session: URLSession,
                        conversationID: UUID, replyID: UUID) async {
        var buffer = ""
        var lastFlush = Date.distantPast

        func flush() {
            guard !buffer.isEmpty else { return }
            append(buffer, to: replyID, in: conversationID)
            buffer = ""
            lastFlush = Date()
        }

        do {
            let failure = try await ChatTransport.stream(request, provider: provider, session: session) { piece in
                buffer += piece
                // Redrawing for every few characters costs more than it shows.
                if Date().timeIntervalSince(lastFlush) > 0.05 { flush() }
            }
            flush()
            finish(conversationID: conversationID, replyID: replyID, failure: failure, stopped: false)
        } catch {
            flush()
            if ChatTransport.isCancellation(error) {
                finish(conversationID: conversationID, replyID: replyID, failure: nil, stopped: true)
            } else {
                finish(conversationID: conversationID, replyID: replyID, failure: .unreachable, stopped: false)
            }
        }
    }
}
