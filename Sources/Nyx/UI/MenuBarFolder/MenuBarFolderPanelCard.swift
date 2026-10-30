import SwiftUI

/// The folder inside the Nyx panel: a switch, the open/close control, and the
/// icons currently tucked inside.
struct MenuBarFolderPanelCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var folder = MenuBarFolderService.shared
    @AppStorage(DefaultsKey.menuBarFolderEnabled) private var enabled = false

    private var text: MenuBarFolderStrings { FeatureStrings.menuBarFolder(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                Text(text.title)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
                Toggle(text.title, isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if enabled {
                HStack(spacing: 8) {
                    Button(folder.isRevealed ? text.hideAgain : text.revealAll) {
                        folder.setRevealed(!folder.isRevealed)
                        folder.refreshHiddenItems()
                    }
                    .controlSize(.small)
                    Button { folder.refreshHiddenItems() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help(text.refresh)
                }
                if folder.closeWasUndone {
                    Text(text.closeUndone)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                MenuBarFolderContents(closesPanel: true)
                Text(text.panelCaption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
        .onChange(of: enabled) { _, on in
            MenuBarFolderService.shared.isEnabled = on
            if on { MenuBarFolderService.shared.refreshHiddenItems() }
        }
        .onAppear {
            if enabled { folder.refreshHiddenItems() }
        }
    }
}

/// The icons inside the folder, kept up to date as icons are put in or taken
/// out. Shared by the Nyx panel and the settings page.
struct MenuBarFolderContents: View {
    var closesPanel = false
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var folder = MenuBarFolderService.shared
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var text: MenuBarFolderStrings { FeatureStrings.menuBarFolder(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.insideTitle + " (\(folder.hiddenItems.count))")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            if folder.hiddenItems.isEmpty {
                Text(text.empty)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(folder.hiddenItems) { item in
                        Button {
                            if closesPanel { appDelegate()?.closePopover() }
                            folder.activate(item)
                        } label: {
                            tile(item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(text.moveOut) {
                                if closesPanel { appDelegate()?.closePopover() }
                                folder.release(item)
                            }
                        }
                        .help(item.name)
                    }
                }
            }
        }
        .onAppear { folder.rescanIfChanged() }
        .onReceive(timer) { _ in folder.rescanIfChanged() }
    }

    @ViewBuilder
    private func tile(_ item: MenuBarFolderService.HiddenItem) -> some View {
        Group {
            if let image = item.image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(height: 18)
            } else if let icon = item.appIcon {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 18, height: 18)
            } else if let symbol = item.symbol {
                Image(systemName: symbol).font(.system(size: 14)).frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed").frame(width: 18, height: 18)
            }
        }
        .frame(minWidth: 34, minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}
