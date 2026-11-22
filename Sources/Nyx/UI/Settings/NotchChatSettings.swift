import SwiftUI

/// Chat's part of the island's Settings page: the keys, how it answers, what
/// it keeps, and how it opens.
struct NotchChatSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChatService.shared
    @AppStorage(DefaultsKey.notchChatSystemPrompt) private var systemPrompt = ""
    @AppStorage(DefaultsKey.notchChatSaveHistory) private var saveHistory = true
    @AppStorage(DefaultsKey.notchChatHistoryLimit) private var historyLimit = ChatHistoryRules.defaultLimit
    @AppStorage(DefaultsKey.notchChatUseSelection) private var useSelection = true
    @AppStorage(DefaultsKey.notchChatSize) private var chatSize = NotchChatSize.large.rawValue
    @AppStorage(DefaultsKey.notchChatShortcutEnabled) private var shortcutEnabled = false
    @AppStorage(DefaultsKey.notchEnabled) private var islandEnabled = false
    @State private var confirmingDelete = false
    private var text: NotchChatStrings { FeatureStrings.notchChat(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !islandEnabled {
                Label(text.needsIsland, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            Text(text.keysHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ChatProvider.allCases) { provider in
                NotchChatKeyRow(provider: provider)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(text.systemPrompt).font(.system(size: 13, weight: .medium))
                TextField(text.systemPromptPlaceholder, text: $systemPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                Text(text.systemPromptHint).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            SettingsRow(symbol: "arrow.up.left.and.arrow.down.right", title: text.sizeTitle, caption: text.sizeHint) {
                Picker(text.sizeTitle, selection: $chatSize) {
                    Text(text.sizeRegular).tag(NotchChatSize.regular.rawValue)
                    Text(text.sizeLarge).tag(NotchChatSize.large.rawValue)
                    Text(text.sizeHuge).tag(NotchChatSize.huge.rawValue)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            SettingsRow(symbol: "text.quote", title: text.useSelection, caption: text.useSelectionHint) {
                Toggle(text.useSelection, isOn: $useSelection).labelsHidden().toggleStyle(NyxSwitchToggleStyle())
            }
            SettingsRow(symbol: "keyboard", title: l10n.s.quickToolShortcutToggle, caption: text.shortcutHint) {
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .labelsHidden().toggleStyle(NyxSwitchToggleStyle())
            }
            if shortcutEnabled {
                ShortcutPreferenceRow(role: .chat) { service.syncWithPreferences() }
                    .padding(.leading, settingsRowTextInset)
                if service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable).font(.caption).foregroundStyle(.orange)
                        .padding(.leading, settingsRowTextInset)
                }
            }
            Divider()
            SettingsRow(symbol: "clock.arrow.circlepath", title: text.saveHistory, caption: text.saveHistoryHint) {
                Toggle(text.saveHistory, isOn: $saveHistory).labelsHidden().toggleStyle(NyxSwitchToggleStyle())
            }
            if saveHistory {
                SettingsRow(symbol: "number", title: text.historyLimit) {
                    Picker(text.historyLimit, selection: $historyLimit) {
                        ForEach(ChatHistoryRules.limits, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden().frame(width: 90)
                }
            }
            SettingsRow(symbol: "trash", title: text.clearHistory) {
                Button(text.clearHistory, role: .destructive) { confirmingDelete = true }
                    .disabled(service.conversations.isEmpty)
            }
            Text(text.privacy).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { service.prepare() }
        .onChange(of: saveHistory) { _, _ in service.historySettingsChanged() }
        .onChange(of: historyLimit) { _, _ in service.historySettingsChanged() }
        .confirmationDialog(text.clearHistoryConfirm, isPresented: $confirmingDelete) {
            Button(text.clearHistory, role: .destructive) { service.deleteAll() }
            Button(text.cancel, role: .cancel) {}
        }
    }
}

/// One service: its key, and once there is one, the model it uses.
private struct NotchChatKeyRow: View {
    let provider: ChatProvider
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChatService.shared
    @State private var key = ""
    @State private var replacing = false
    @FocusState private var keyFocused: Bool
    @State private var problem: String?
    @State private var modelText = ""
    private var text: NotchChatStrings { FeatureStrings.notchChat(l10n.language) }
    private var saved: Bool { service.hasKey(for: provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(symbol: provider.symbol, title: provider.displayName,
                        caption: saved ? text.keySaved : text.keyNone) {
                if saved && !replacing {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Button(text.replace) { replacing = true }
                        Button(text.remove, role: .destructive) { service.removeKey(for: provider) }
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField(provider.keyPlaceholder, text: $key)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 140, maxWidth: 210)
                            .focused($keyFocused)
                            .onSubmit(connect)
                            .chatKeyPaste(active: keyFocused) { handlePasted($0) }
                        Button(text.paste, action: pasteAndConnect).disabled(service.checkingKey)
                        Button(service.checkingKey ? text.connecting : text.save, action: connect)
                            .disabled(key.isEmpty || service.checkingKey)
                        if replacing { Button(text.cancel) { replacing = false; key = ""; problem = nil } }
                    }
                }
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.orange).padding(.leading, settingsRowTextInset) }
            if saved { modelRow }
        }
        .onAppear { modelText = service.model(for: provider) }
        .onChange(of: saved) { _, _ in modelText = service.model(for: provider) }
    }

    private var modelRow: some View {
        SettingsRow(symbol: "cube", title: text.model) {
            HStack(spacing: 6) {
                TextField(provider.fallbackModel, text: $modelText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 140, maxWidth: 220)
                    .onSubmit { service.setModel(modelText, for: provider) }
                let models = service.models[provider] ?? []
                Menu {
                    ForEach(models.prefix(60)) { model in
                        Button(model.name) { modelText = model.id; service.setModel(model.id, for: provider) }
                    }
                    if !models.isEmpty { Divider() }
                    Button(text.refreshModels) { service.refreshModels(for: provider) }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(text.refreshModels)
            }
        }
        .padding(.leading, settingsRowTextInset)
    }

    private func pasteAndConnect() {
        GeneralPasteboardAccess.shared.async({ NSPasteboard.general.string(forType: .string) }) { copied in
            handlePasted(copied ?? "")
        }
    }

    private func handlePasted(_ pasted: String) {
        if let found = ChatProvider.extractKey(from: pasted) { key = found; connect() }
        else { problem = ChatProvider.isSnippetWithoutKey(pasted) ? text.snippetNoKey : text.keyLooksWrong }
    }

    private func connect() {
        guard ChatProvider.looksLikeKey(key) else { problem = text.keyLooksWrong; return }
        problem = nil
        let chosen = provider
        service.connect(chosen, key: key) { failure in
            if let failure { problem = text.failure(failure, provider: chosen) } else { key = ""; replacing = false }
        }
    }
}
