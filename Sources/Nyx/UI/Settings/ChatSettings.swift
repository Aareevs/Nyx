import SwiftUI

/// Chat's page in Settings: its keys and everything else it can be set to.
struct ChatSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.notchChatEnabled) private var enabled = true
    private var text: NotchChatStrings { FeatureStrings.notchChat(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(text.title).font(.title2.bold())
                        Text(text.description).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle(text.enable, isOn: $enabled).labelsHidden().toggleStyle(NyxSwitchToggleStyle())
                        .disabled(!AppFeature.notchChat.isAvailable).accessibilityLabel(text.enable)
                }
                SettingsCard { NotchChatSettingsControls() }
                if AppFeature.notchChat.isAvailable, NotchSupport.isEnabled() {
                    Button(FeatureStrings.notchChat(l10n.language).title) { NotchService.shared.openChat() }
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 22)
        }
    }
}
