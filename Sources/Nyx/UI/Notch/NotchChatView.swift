import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The chat page: the conversation above, the field below. Without a key it
/// asks for one right here, so there is no trip to Settings first.
struct NotchChatView: View {
    let size: CGSize
    @Environment(\.notchSettingsPreview) private var preview
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChatService.shared
    @State private var addingKey = false
    @State private var showingHistory = false
    @State private var hoveredChat: UUID?
    @State private var setupProvider = ChatProvider.claude
    @State private var filePanel: NSOpenPanel?
    @FocusState private var composing: Bool
    private var text: NotchChatStrings { FeatureStrings.notchChat(l10n.language) }

    var body: some View {
        Group {
            if preview {
                emptyState
            } else if !service.hasKey || addingKey {
                NotchChatSetup(provider: setupProvider, canCancel: service.hasKey) { addingKey = false }
            } else {
                conversation
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            guard !preview else { return }
            service.prepare()
            setupProvider = service.provider
            if service.hasKey, service.models[service.provider] == nil { service.refreshModels(for: service.provider) }
            composing = true
        }
        .onChange(of: service.focusSerial) { _, _ in composing = true }
        // The island takes the keyboard just after the page appears, so the
        // field asks again once its window is key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if !preview, service.hasKey, !addingKey { composing = true }
        }
        .notchBand(leading: {
            if !preview, service.hasKey, !addingKey { modelMenu }
        }, trailing: {
            if !preview, service.hasKey, !addingKey {
                NotchIconButton(symbol: "sidebar.left", title: text.history, selected: showingHistory) {
                    showingHistory.toggle()
                }
                NotchIconButton(symbol: "square.and.pencil", title: text.newChat) {
                    service.newChat()
                    composing = true
                }
            }
        })
    }

    // MARK: Conversation

    private var conversation: some View {
        HStack(alignment: .top, spacing: 12) {
            if showingHistory {
                historyPanel
                    .frame(width: 208)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            thread
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // While the list is open, a click in the chat closes it too;
                // buttons and text inside the chat still work as usual.
                .simultaneousGesture(TapGesture().onEnded { if showingHistory { showingHistory = false } })
        }
        .animation(.smooth(duration: 0.22), value: showingHistory)
    }

    // MARK: History

    /// The chats of the service in use, grouped by how long ago, as a sidebar.
    private var historyPanel: some View {
        let provider = service.provider
        let sections = ChatHistoryRules.sections(service.providerConversations)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                service.newChat()
                composing = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil").font(.system(size: 12, weight: .medium))
                    Text(text.newChat).font(.system(size: 12.5, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10).frame(height: 32)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Text(String(format: text.chatsOf, provider.displayName))
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 4).padding(.top, 2)

            if sections.isEmpty {
                Text(text.noHistory).font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity).padding(.top, 20)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sections, id: \.bucket) { section in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(text.title(of: section.bucket))
                                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.38))
                                    .padding(.horizontal, 8).padding(.bottom, 2)
                                ForEach(section.chats) { chat in historyRow(chat) }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
                .notchScrollEdgeFade(.vertical, length: 12)
            }
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func historyRow(_ chat: ChatConversation) -> some View {
        let selected = chat.id == service.currentID
        let hovering = hoveredChat == chat.id
        return HStack(spacing: 6) {
            Text(chat.title.isEmpty ? text.newChat : chat.title)
                .font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.8))
            Spacer(minLength: 0)
            if hovering {
                Button { service.delete(chat.id) } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(text.deleteChat)
                .accessibilityLabel(text.deleteChat)
            }
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(.white.opacity(selected ? 0.14 : (hovering ? 0.07 : 0)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { service.open(chat.id) }
        .onHover { inside in hoveredChat = inside ? chat.id : (hoveredChat == chat.id ? nil : hoveredChat) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(chat.title)
    }

    private var thread: some View {
        VStack(spacing: 10) {
            if service.messages.isEmpty { emptyState } else { messageList }
            if let failure = service.failure {
                failureRow(failure)
            } else if service.canRetry {
                HStack { Spacer(); NotchPillButton(title: text.retry) { service.retry() } }
            }
            composer
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text(text.emptyTitle).font(.system(size: 13, weight: .semibold))
            Text(text.emptyHint).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: a lazy list pinned to the bottom can leave the new message
                // unpainted until the next scroll, and a chat is short enough to build whole.
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(service.messages) { message in
                        NotchChatMessageView(message: message,
                                             symbol: (service.current?.provider ?? service.provider).symbol,
                                             waiting: service.isStreaming && message.id == service.messages.last?.id
                                                && message.text.isEmpty,
                                             copyLabel: text.copy, copiedLabel: text.copied,
                                             selectedLabel: text.selectedText,
                                             stoppedLabel: text.interrupted)
                            .equatable()
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 10)
            }
            .notchScrollEdgeFade(.vertical, length: 14)
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.never)
            .onChange(of: service.messages.count) { _, _ in
                // After the new rows have their size, so the scroll lands on the end.
                DispatchQueue.main.async { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private func failureRow(_ failure: ChatFailure) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text.failure(failure, provider: service.provider))
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.8))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if failure == .noKey {
                NotchPillButton(title: text.connect) { setupProvider = service.provider; addingKey = true }
            } else if service.canRetry {
                NotchPillButton(title: text.retry) { service.retry() }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 6) {
            if let attachment = service.attachment { attachmentChip(attachment) }
            if !service.files.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(service.files) { file in
                            ChatFileCard(name: file.name, symbol: file.symbol,
                                         image: file.symbol == "photo" ? file.images.first : nil,
                                         note: file.truncated ? text.cutShort : nil) { service.removeFile(file) }
                        }
                    }
                    .padding(.top, 6).padding(.trailing, 6)
                }
                .scrollIndicators(.never)
            }
            if service.readingFiles {
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(text.readingFile).font(.system(size: 11)) }
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let problem = service.fileProblem {
                Text(problem).font(.system(size: 11)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button { chooseFiles() } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(text.addFile)
                .accessibilityLabel(text.addFile)

                Button { service.attachClipboard() } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(text.addClipboard)
                .accessibilityLabel(text.addClipboard)

                TextField(text.placeholder, text: $service.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                    .focused($composing)
                    .onSubmit { if service.canSend { service.send() } }
                    .padding(.vertical, 3)

                if service.isStreaming {
                    sendButton(symbol: "stop.fill", title: text.stop, enabled: true) { service.stopStreaming() }
                } else {
                    sendButton(symbol: "arrow.up", title: text.send, enabled: service.canSend) { service.send() }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 1))
        }
    }

    private func sendButton(symbol: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.35))
                .frame(width: 28, height: 28)
                .background(enabled ? AnyShapeStyle(NotchChatStyle.accent) : AnyShapeStyle(Color.white.opacity(0.12)), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(title)
        .accessibilityLabel(title)
    }

    /// Opens the file picker just above the island, which stays open meanwhile.
    private func chooseFiles() {
        guard filePanel == nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ChatFileReader.allExtensions.compactMap { UTType(filenameExtension: $0) }
        filePanel = panel
        let notch = NotchService.shared
        notch.keepFileInteractionOpen(true)
        let finished: (NSApplication.ModalResponse) -> Void = { response in
            filePanel = nil
            notch.keepFileInteractionOpen(false)
            if response == .OK { service.attachFiles(panel.urls) }
        }
        guard let island = notch.presentationWindow, island.isVisible else {
            NSApp.activate(ignoringOtherApps: true)
            panel.begin(completionHandler: finished)
            return
        }
        panel.level = NSWindow.Level(rawValue: island.level.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.begin { response in
            finished(response)
            DispatchQueue.main.async { if notch.expanded { island.makeKey() } }
        }
    }

    private func attachmentChip(_ attachment: ChatAttachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.fromClipboard ? "doc.on.clipboard" : "text.quote")
                .font(.system(size: 10, weight: .semibold))
            Text(attachment.text.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Button { service.attachment = nil } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(text.removeAttachment)
            .accessibilityLabel(text.removeAttachment)
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.white.opacity(0.07), in: Capsule())
    }

    // MARK: Menus

    private var modelMenu: some View {
        let provider = service.provider
        let models = service.models[provider] ?? []
        let current = service.model(for: provider)
        return Menu {
            Section(text.provider) {
                ForEach(ChatProvider.allCases) { choice in
                    Button { choose(choice) } label: {
                        let name = service.hasKey(for: choice) ? choice.displayName : "\(choice.displayName) — \(text.connect)"
                        if choice == provider { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            }
            Section(text.model) {
                if models.isEmpty {
                    Text(current)
                } else {
                    ForEach(models.prefix(40)) { model in
                        Button { service.setModel(model.id, for: provider) } label: {
                            if model.id == current { Label(model.name, systemImage: "checkmark") } else { Text(model.name) }
                        }
                    }
                }
                Button(text.refreshModels) { service.refreshModels(for: provider) }
            }
            Section(provider.displayName) {
                Button(text.changeKey) { setupProvider = provider; addingKey = true }
                Button(text.removeKey, role: .destructive) { service.removeKey(for: provider) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: provider.symbol).font(.system(size: 10, weight: .semibold))
                Text(provider.displayName).font(.system(size: 11, weight: .semibold))
                Text(Self.shortName(current)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 170)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(.white.opacity(0.1), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(provider.displayName) · \(current)")
    }

    /// The part of a model's name a person reads: "meta/llama-3-70b" is "llama-3-70b".
    static func shortName(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
    }

    private func choose(_ provider: ChatProvider) {
        if service.hasKey(for: provider) {
            service.provider = provider
            if service.models[provider] == nil { service.refreshModels(for: provider) }
        } else {
            setupProvider = provider
            addingKey = true
        }
    }
}

/// One message: the person's in a bubble, the reply as plain text with its
/// code in boxes.
/// The colours the conversation is drawn in.
enum NotchChatStyle {
    static let accent = LinearGradient(colors: [Color(red: 0.32, green: 0.54, blue: 1.0), Color(red: 0.22, green: 0.40, blue: 0.95)],
                                       startPoint: .top, endPoint: .bottom)
}

private struct NotchChatMessageView: View, Equatable {
    let message: ChatMessage
    let symbol: String
    let waiting: Bool
    let copyLabel: String
    let copiedLabel: String
    let selectedLabel: String
    let stoppedLabel: String
    @State private var copiedBlock: Int?
    @State private var copiedWhole = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.waiting == rhs.waiting && lhs.symbol == rhs.symbol
            && lhs.copyLabel == rhs.copyLabel && lhs.copiedLabel == rhs.copiedLabel
    }

    var body: some View {
        switch message.role {
        case .user: user
        case .assistant: assistant
        }
    }

    /// The message's files, each with its picture while the app still has it.
    private var sentFiles: [(file: ChatFileInfo, image: ChatImage?)] {
        var offset = 0
        return message.files.map { file in
            let count = file.imageCount ?? 0
            defer { offset += count }
            let image = file.symbol == "photo" && message.images.indices.contains(offset) ? message.images[offset] : nil
            return (file, image)
        }
    }

    private var user: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 64)
            VStack(alignment: .trailing, spacing: 5) {
                if let context = message.context, !context.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "text.quote").font(.system(size: 9, weight: .semibold))
                        Text(context.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 10.5)).lineLimit(2)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel(selectedLabel)
                }
                if !message.files.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(sentFiles.enumerated()), id: \.offset) { _, entry in
                            ChatFileCard(name: entry.file.name, symbol: entry.file.symbol, image: entry.image, note: nil, remove: nil)
                        }
                    }
                }
                Text(message.text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(NotchChatStyle.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var assistant: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.1), in: Circle())
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 9) {
                if waiting {
                    ProgressView().controlSize(.small).padding(.vertical, 5)
                } else {
                    let blocks = ChatMarkdown.blocks(message.text)
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        switch block {
                        case .text(let value):
                            Text(Self.attributed(value))
                                .font(.system(size: 13.5))
                                .foregroundStyle(.white.opacity(0.94))
                                .lineSpacing(3.5)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        case .code(let language, let code):
                            codeBox(index: index, language: language, code: code)
                        }
                    }
                    if message.interrupted {
                        Text(stoppedLabel).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    }
                    if !message.text.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                            copiedWhole = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copiedWhole = false }
                        } label: {
                            Label(copiedWhole ? copiedLabel : copyLabel,
                                  systemImage: copiedWhole ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.38))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 28)
        }
    }

    private func codeBox(index: Int, language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copiedBlock = index
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if copiedBlock == index { copiedBlock = nil } }
                } label: {
                    Label(copiedBlock == index ? copiedLabel : copyLabel,
                          systemImage: copiedBlock == index ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.white.opacity(0.06))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(Self.highlighted(code, language: language))
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(2.5)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .background(Color(red: 0.09, green: 0.10, blue: 0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The code with its keywords, strings, numbers, comments, types and calls coloured.
    static func highlighted(_ code: String, language: String) -> AttributedString {
        var result = AttributedString()
        for run in ChatSyntax.runs(code, language: language) {
            var piece = AttributedString(run.text)
            piece.foregroundColor = color(run.kind)
            if run.kind == .comment { piece.font = .system(size: 12, design: .monospaced).italic() }
            result += piece
        }
        return result
    }

    private static func color(_ kind: ChatSyntax.Kind) -> Color {
        switch kind {
        case .plain: return Color.white.opacity(0.92)
        case .keyword: return Color(red: 1.00, green: 0.49, blue: 0.70)
        case .string: return Color(red: 0.62, green: 0.89, blue: 0.52)
        case .number: return Color(red: 1.00, green: 0.74, blue: 0.40)
        case .comment: return Color(red: 0.48, green: 0.55, blue: 0.62)
        case .type: return Color(red: 0.42, green: 0.84, blue: 0.96)
        case .call: return Color(red: 0.58, green: 0.74, blue: 1.00)
        }
    }

    /// Bold, italic, code and links from the reply's own markdown; headings and
    /// bullets become plain text that reads the same.
    static func attributed(_ source: String) -> AttributedString {
        let prepared = ChatMarkdown.prepared(source)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(prepared)
    }
}

/// Asks for a key without leaving the island.
struct NotchChatSetup: View {
    @State var provider: ChatProvider
    let canCancel: Bool
    let done: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChatService.shared
    @State private var key = ""
    @State private var problem: String?
    @FocusState private var focused: Bool
    private var text: NotchChatStrings { FeatureStrings.notchChat(l10n.language) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 17, weight: .light)).foregroundStyle(.white.opacity(0.55))
                Text(text.setupTitle).font(.system(size: 13, weight: .semibold))
            }
            // A problem takes the hint's place, so the page never outgrows the island.
            if let problem {
                Text(problem).font(.system(size: 11.5)).foregroundStyle(.orange)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text.setupHint).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 4) {
                ForEach(ChatProvider.allCases) { choice in
                    Button { pick(choice) } label: {
                        Text(choice.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(provider == choice ? .white : .white.opacity(0.5))
                            .frame(maxWidth: .infinity).frame(height: 24)
                            .background(.white.opacity(provider == choice ? 0.14 : 0),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(provider == choice ? .isSelected : [])
                }
            }
            .padding(3)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .frame(maxWidth: 380)

            HStack(spacing: 8) {
                SecureField(provider.keyPlaceholder, text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .focused($focused)
                    .onSubmit(connect)
                    .chatKeyPaste(active: focused) { handlePasted($0) }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                NotchPillButton(title: text.paste, action: pasteAndConnect)
                    .disabled(service.checkingKey)
                NotchPillButton(title: service.checkingKey ? text.connecting : text.connect, prominent: true, action: connect)
                    .disabled(service.checkingKey || key.isEmpty)
            }
            .frame(maxWidth: 420)

            if canCancel { NotchPillButton(title: text.cancel, action: done) }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in focused = true }
    }

    /// A service that already has a key is simply used: no reason to ask for
    /// its key again. One without a key is set up here.
    private func pick(_ choice: ChatProvider) {
        problem = nil
        guard choice != provider, service.hasKey(for: choice) else { provider = choice; return }
        service.provider = choice
        if service.models[choice] == nil { service.refreshModels(for: choice) }
        done()
    }

    /// Takes the key from the clipboard, whether it was copied alone or as a
    /// whole code snippet, and connects with it.
    private func pasteAndConnect() {
        GeneralPasteboardAccess.shared.async({ NSPasteboard.general.string(forType: .string) }) { copied in
            handlePasted(copied ?? "")
        }
    }

    /// Text that was pasted, a key or a snippet holding one: connect with the key
    /// in it, or say why there is none.
    private func handlePasted(_ pasted: String) {
        if let found = ChatProvider.extractKey(from: pasted) {
            key = found
            connect()
        } else {
            problem = ChatProvider.isSnippetWithoutKey(pasted) ? text.snippetNoKey : text.keyLooksWrong
        }
    }

    private func connect() {
        guard ChatProvider.looksLikeKey(key) else { problem = text.keyLooksWrong; return }
        problem = nil
        let chosen = provider
        service.connect(chosen, key: key) { failure in
            if let failure {
                problem = text.failure(failure, provider: chosen)
            } else {
                key = ""
                done()
            }
        }
    }
}

/// A file as a card, as chat apps show it: a picture's own preview, or an
/// icon with the name and kind. With `remove`, a small button takes it back.
struct ChatFileCard: View {
    let name: String
    let symbol: String
    let image: ChatImage?
    let note: String?
    let remove: (() -> Void)?

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                if let remove {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                            .foregroundStyle(.white, Color(white: 0.3))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("Remove")
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let picture = ChatThumbnails.image(for: image) {
            Image(nsImage: picture).resizable().scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
                .accessibilityLabel(name)
        } else {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text([kind, note].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: 190, alignment: .leading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1)))
        }
    }

    private var kind: String? {
        let ext = (name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? nil : ext
    }
}

/// Decoded previews, kept so a thread does not decode a picture on every redraw.
@MainActor
enum ChatThumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for picture: ChatImage?) -> NSImage? {
        guard let picture else { return nil }
        let key = "\(picture.base64.count)-\(picture.base64.prefix(48))-\(picture.base64.suffix(48))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = Data(base64Encoded: picture.base64), let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
