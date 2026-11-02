import AppKit
import SwiftUI

/// The color picker as a panel: a gradient square and hue slider, the value in
/// HEX, RGB and HSL, contrast against white and black, and the colors picked
/// lately. "Pick from screen" hands the result back here instead of copying it
/// straight away. It floats near the top of the screen with the pointer, closes
/// on Esc and remembers the last color it showed.
final class ColorPickerPanelService: ObservableObject {
    static let shared = ColorPickerPanelService()

    @Published var color: ColorPickerColor {
        didSet { defaults.set(hex(bare: false), forKey: DefaultsKey.colorPickerLast) }
    }
    @Published private(set) var recents: [String]

    private let defaults = UserDefaults.standard
    private var panel: NSPanel?

    private final class KeyablePanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
        /// Esc, wherever focus is inside the panel.
        override func cancelOperation(_ sender: Any?) {
            ColorPickerPanelService.shared.hide()
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.colorPickerLast) ?? ColorPickerMath.defaultHex
        let rgb = ColorPickerMath.rgb(fromHex: stored) ?? ColorPickerMath.rgb(fromHex: ColorPickerMath.defaultHex)!
        color = ColorPickerMath.color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.colorPickerRecent),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            recents = Array(saved.filter { ColorPickerMath.rgb(fromHex: $0) != nil }.prefix(ColorPickerMath.recentLimit))
        } else {
            recents = []
        }
    }

    // MARK: Value

    var rgb: (red: Double, green: Double, blue: Double) { ColorPickerMath.rgb(from: color) }

    func hex(bare: Bool) -> String {
        let c = rgb
        return ColorPickerMath.hex(red: c.red, green: c.green, blue: c.blue, bare: bare)
    }

    func select(hex text: String) {
        guard let rgb = ColorPickerMath.rgb(fromHex: text) else { return }
        color = ColorPickerMath.color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    // MARK: Recents

    func addCurrentToRecents() {
        recents = ColorPickerMath.addingRecent(hex(bare: false), to: recents)
        saveRecents()
    }

    func clearRecents() {
        recents = []
        saveRecents()
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: DefaultsKey.colorPickerRecent)
        }
    }

    // MARK: Picking from the screen

    /// A sampled color lands in the panel and in the recent list.
    func receive(_ sampled: NSColor) {
        guard let srgb = sampled.usingColorSpace(.sRGB) else { return }
        color = ColorPickerMath.color(red: Double(srgb.redComponent),
                                      green: Double(srgb.greenComponent),
                                      blue: Double(srgb.blueComponent))
        addCurrentToRecents()
        show()
    }

    func pickFromScreen() {
        ColorSamplerService.shared.deliversToPanel = true
        if Permissions.shared.screenRecording {
            ScreenCaptureService.shared.capture(initial: .color, opensColorPanel: false)
        } else {
            // Sampling a pixel needs no capture permission.
            ColorSamplerService.shared.pickNative()
        }
    }

    // MARK: Window

    var isShown: Bool { panel?.isVisible == true }

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard AppFeature.colorPicker.isAvailable else { return }
        let panel = ensurePanel()
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        ColorSamplerService.shared.deliversToPanel = false
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.title = "Nyx"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ColorPickerPanelView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 560, height: 300)
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.maxY - size.height - 120
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, y),
                              width: size.width, height: size.height),
                       display: true, animate: false)
    }
}
