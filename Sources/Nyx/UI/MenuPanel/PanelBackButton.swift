import SwiftUI

private struct PanelBackHiddenKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// A host that already shows the way back (the island's top row) sets this.
    var panelBackHidden: Bool {
        get { self[PanelBackHiddenKey.self] }
        set { self[PanelBackHiddenKey.self] = newValue }
    }
}

/// The way back from a tool to the list it was opened from, leading the
/// tool's header.
struct PanelBackButton: View {
    var action: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.panelBackHidden) private var hidden

    var body: some View {
        if !hidden { button }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(l10n.s.obBack)
        .accessibilityLabel(l10n.s.obBack)
    }
}
