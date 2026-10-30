import AppKit
import SwiftUI

/// The strip of hidden icons that drops from the folder.
final class MenuBarFolderPanel: OverlayPanel {
    private let model: MenuBarFolderPanelModel

    init(items: [MenuBarFolderService.HiddenItem], emptyText: String, accessibilityHint: String?,
         onSelect: @escaping (MenuBarFolderService.HiddenItem) -> Void,
         onRelease: @escaping (MenuBarFolderService.HiddenItem) -> Void) {
        model = MenuBarFolderPanelModel(items: items)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let host = NSHostingView(rootView: MenuBarFolderPanelView(model: model, emptyText: emptyText,
                                                                  hint: accessibilityHint, onSelect: onSelect,
                                                                  onRelease: onRelease))
        contentView = host
        setContentSize(host.fittingSize)
    }

    override var canBecomeKey: Bool { false }

    func update(id: CGWindowID, image: NSImage) {
        model.setImage(image, for: id)
    }

    func present(below folderFrame: NSRect) {
        guard let host = contentView else { return }
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(folderFrame) && folderFrame.maxX > $0.frame.minX }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = folderFrame.maxX - 13 - size.width / 2
        x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
        setFrame(NSRect(x: x, y: visible.maxY - size.height - 6, width: size.width, height: size.height),
                 display: true)
        orderFrontRegardless()
    }
}

final class MenuBarFolderPanelModel: ObservableObject {
    @Published var items: [MenuBarFolderService.HiddenItem]
    init(items: [MenuBarFolderService.HiddenItem]) { self.items = items }

    func setImage(_ image: NSImage, for id: CGWindowID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].image = image
    }
}

private struct MenuBarFolderPanelView: View {
    @ObservedObject var model: MenuBarFolderPanelModel
    let emptyText: String
    let hint: String?
    var releaseTitle: String { FeatureStrings.menuBarFolder(L10n.shared.language).moveOut }
    let onSelect: (MenuBarFolderService.HiddenItem) -> Void
    let onRelease: (MenuBarFolderService.HiddenItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.items.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 250, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 4) {
                    ForEach(model.items) { item in
                        tile(item)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .contentShape(Rectangle())
                            // A click uses the icon; dragging it away takes it
                            // back out of the folder.
                            .onTapGesture { onSelect(item) }
                            .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                                if hypot(value.translation.width, value.translation.height) > 24 { onRelease(item) }
                            })
                            .contextMenu {
                                Button(releaseTitle) { onRelease(item) }
                            }
                            .help(item.name)
                            .accessibilityLabel(item.name)
                    }
                }
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .padding(2)
    }

    @ViewBuilder
    private func tile(_ item: MenuBarFolderService.HiddenItem) -> some View {
        Group {
            if let image = item.image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: max(18, min(image.size.width, 44)), height: 18)
            } else if let icon = item.appIcon {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed").frame(width: 18, height: 18)
            }
        }
        .padding(7)
    }
}

private struct FolderTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.2 : 0.06))
            )
    }
}
