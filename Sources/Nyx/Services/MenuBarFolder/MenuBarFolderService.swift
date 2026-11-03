import AppKit
import ApplicationServices
import ScreenCaptureKit

/// A folder for menu bar icons. Two status items: the visible folder, and an
/// invisible spacer created beside it, to its left. While the folder is closed
/// the spacer is very wide, which pushes every icon to its left past the screen
/// edge. The folder's panel, and the Nyx panel, list those icons, and clicking
/// one forwards the click to the real icon.
///
/// Closing the folder checks that the folder icon itself is still on screen
/// afterwards, and opens it again when it is not, so it cannot strand the menu
/// bar.
final class MenuBarFolderService: NSObject, ObservableObject {
    static let shared = MenuBarFolderService()

    struct HiddenItem: Identifiable {
        let id: CGWindowID
        let pid: pid_t
        let name: String
        let appIcon: NSImage?
        var image: NSImage?
        /// Stays the same between launches, unlike the window number, so the
        /// picture of an icon can be found again once it is tucked away.
        var identity = ""
        /// A stand-in for macOS's own icons when no picture of them could be taken.
        var symbol: String?
    }

    private static let systemSymbols: [String: String] = [
        "WiFi": "wifi", "Battery": "battery.100", "Sound": "speaker.wave.2.fill", "Bluetooth": "dot.radiowaves.left.and.right",
        "Display": "sun.max.fill", "FocusModes": "moon.fill", "ScreenMirroring": "rectangle.on.rectangle",
        "Spotlight": "magnifyingglass", "Siri": "waveform", "NowPlaying": "play.rectangle.fill",
        "KeyboardBrightness": "light.max", "UserSwitcher": "person.crop.circle", "Accessibility": "accessibility",
        "StageManager": "rectangle.3.group"
    ]

    /// Pictures of tucked-away icons, kept on disk: an icon off the screen
    /// cannot be photographed again, so a restart would otherwise lose them.
    private enum PictureStore {
        static var folder: URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return base.appending(path: Bundle.main.bundleIdentifier ?? "Nyx", directoryHint: .isDirectory)
                .appending(path: "MenuBarFolder", directoryHint: .isDirectory)
        }

        private static func file(_ identity: String) -> URL {
            let safe = identity.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
            return folder.appending(path: String(safe) + ".png")
        }

        static func load(_ identity: String) -> NSImage? {
            identity.isEmpty ? nil : NSImage(contentsOf: file(identity))
        }

        static func save(_ image: NSImage, identity: String) {
            guard !identity.isEmpty, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png.write(to: file(identity), options: .atomic)
        }
    }

    /// The app behind an icon where macOS says so, else the icon's own title.
    private static func identity(pid: pid_t, controlCentrePID: pid_t?, title: String, width: CGFloat) -> String {
        if pid != controlCentrePID, let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            return bundle + "|" + title + "|\(Int(width))"
        }
        return "title|" + title + "|\(Int(width))"
    }

    private static let hiddenWidth: CGFloat = 9_000
    /// The open spacer is only a few points wide and draws nothing.
    private static let openWidth: CGFloat = 4
    private static let barLayer = 25   // kCGStatusWindowLevel
    /// Autosave names double as the window titles of our own items.
    private static let folderName = "NyxMenuBarFolder"
    private static let spacerName = "NyxMenuBarFolderSpacer"
    private static func positionKey(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }
    /// Menu bar items that stay where they are. Everything else, including
    /// macOS's own Wi-Fi, Battery and Sound, can be put in the folder.
    private static let systemTitles: Set<String> = [
        // Fixed by macOS, so they cannot be moved into the folder.
        "Clock", "ControlCenter", "AudioVideoModule", "NyxMenuBarItem"
    ]

    @Published private(set) var isRevealed = true
    @Published private(set) var hiddenItems: [HiddenItem] = []
    /// Set when closing the folder was undone because it made the folder icon
    /// vanish, which happens on a menu bar with no room to spare.
    @Published private(set) var closeWasUndone = false

    private var item: NSStatusItem?
    private var spacer: NSStatusItem?
    private var panel: MenuBarFolderPanel?
    private var outsideClickMonitor: Any?
    private var recollapseMonitor: Any?
    private var recollapseTimer: Timer?
    private var orderRepairTried = false
    private var dragMonitors: [Any] = []
    private var dragSnapshot: [CGWindowID: CGFloat] = [:]
    private var isAbsorbing = false
    /// Pictures taken while an icon was still on screen; an icon pushed off
    /// the screen cannot be photographed any more.
    private var imageCache: [CGWindowID: NSImage] = [:]

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.menuBarFolderEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.menuBarFolderEnabled)
            newValue ? start() : stop()
        }
    }

    var isRunning: Bool { item != nil }

    private var text: MenuBarFolderStrings { FeatureStrings.menuBarFolder(L10n.shared.language) }

    // MARK: - Lifecycle

    func startIfEnabled() {
        if isEnabled { start() }
    }

    /// macOS remembers where each item sat and lays them out by that number.
    /// Putting the spacer's below the folder's keeps it on the folder's left.
    private func seedPositions(swapped: Bool = false) {
        let defaults = UserDefaults.standard
        let anchor = defaults.object(forKey: Self.positionKey("NyxMenuBarItem")) as? Double ?? 500
        defaults.set(anchor + (swapped ? 40 : 80), forKey: Self.positionKey(Self.folderName))
        defaults.set(anchor + (swapped ? 80 : 40), forKey: Self.positionKey(Self.spacerName))
    }

    /// Where Nyx's own icon sits, and a way to put it back right of the folder.
    var placeMainItem: ((Double) -> Void)?
    private var mainPlacementTried = false

    func start() {
        guard item == nil else { return }
        if UserDefaults.standard.object(forKey: Self.positionKey(Self.folderName)) == nil { seedPositions() }
        let folder = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        folder.autosaveName = Self.folderName
        if let button = folder.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: text.folderHelp)
            button.toolTip = text.folderHelp
        }
        let spacerItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        spacerItem.autosaveName = Self.spacerName
        item = folder
        spacer = spacerItem
        isRevealed = true
        closeWasUndone = false
        applySpacerImage()
        installDragMonitors()
        // Once macOS has laid the items out: fix a wrong order, then tuck away
        // again when icons were already put inside earlier.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.item != nil else { return }
            if self.spacerIsRightOfFolder(), !self.orderRepairTried {
                self.orderRepairTried = true
                self.repairOrder()
                return
            }
            // Nyx's own icon belongs on the folder's right. When macOS laid it
            // out on the left, put it back there once, and do not collapse
            // until it has settled.
            // The items' own frames read zero here; the window list has them.
            let mainName = StatusItemPlacementSupport.mainAutosaveName(in: .standard)
            if !self.mainPlacementTried, let main = self.ownWindow(titled: mainName)?.bounds.minX,
               let folder = self.ownWindow(titled: Self.folderName)?.bounds.minX, main < folder,
               let place = self.placeMainItem {
                self.mainPlacementTried = true
                place(UserDefaults.standard.object(forKey: Self.positionKey(Self.folderName)) as? Double ?? 500)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self, self.item != nil else { return }
                    self.captureThenClose()
                }
                return
            }
            self.captureThenClose()
        }
    }

    /// Photographs the icons in the folder while they can still be seen, then
    /// tucks them away. A picture can only be taken while the menu bar is
    /// showing, so with it auto-hidden this keeps trying for a while.
    private func captureThenClose(attempt: Int = 0) {
        hiddenItems = scanHiddenItems()
        guard !hiddenItems.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.captureImagesNow(ids: self.hiddenItems.map(\.id))
            // Icons with a stand-in picture do not hold the folder open.
            if self.hiddenItems.contains(where: { $0.image == nil && $0.symbol == nil && $0.appIcon == nil }), attempt < 30 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard self.item != nil, self.isRevealed else { return }
                self.captureThenClose(attempt: attempt + 1)
                return
            }
            self.setRevealed(false)
        }
    }

    func stop() {
        returnTempShown()
        closePanel()
        cancelRecollapse()
        dragMonitors.forEach { NSEvent.removeMonitor($0) }
        dragMonitors = []
        if let item { NSStatusBar.system.removeStatusItem(item) }
        if let spacer { NSStatusBar.system.removeStatusItem(spacer) }
        item = nil
        spacer = nil
        isRevealed = true
        hiddenItems = []
    }

    private func spacerIsRightOfFolder() -> Bool {
        guard let folder = item?.button?.window?.frame, let spacer = spacerFrameOrFolder else { return false }
        return spacer.minX > folder.minX
    }

    /// The saved numbers left the spacer on the wrong side; flip them and build
    /// the items again.
    private func repairOrder() {
        stop()
        seedPositions(swapped: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.start() }
    }

    // MARK: - Opening and closing

    /// Opens or closes the room the hidden icons live in.
    func setRevealed(_ revealed: Bool) {
        guard isRevealed != revealed, item != nil else { return }
        isRevealed = revealed
        item?.button?.image = NSImage(systemSymbolName: revealed ? "folder.fill" : "folder",
                                      accessibilityDescription: text.folderHelp)
        if revealed {
            // In two steps, so the icons glide in: the spacer shrinks first,
            // and only once they have settled is it taken out of the bar.
            shrinkSpacer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.isRevealed else { return }
                self.applySpacerImage()
            }
        } else {
            applySpacerImage()
            verifyFolderStillVisible()
        }
    }

    /// Open, the spacer is a few blank points wide; closed, it is wide enough
    /// to push everything to its left off the screen. Either way it draws
    /// nothing, so the folder is the only thing to see.
    /// The spacer's frame, or the folder's left edge while the spacer is
    /// taken out of the bar so no gap is left beside the folder.
    private var spacerFrameOrFolder: CGRect? {
        if let frame = spacer?.button?.window?.frame { return frame }
        guard let folder = item?.button?.window?.frame else { return nil }
        return CGRect(x: folder.minX, y: folder.minY, width: 0, height: folder.height)
    }

    private func shrinkSpacer() {
        guard let button = spacer?.button else { return }
        let image = NSImage(size: NSSize(width: 4, height: 1), flipped: false) { _ in true }
        image.isTemplate = true
        button.image = image
    }

    private func makeSpacer() -> NSStatusItem {
        // Removing an item forgets where it sat, and an earlier build left it
        // marked as hidden: put it back just left of the folder.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "NSStatusItem VisibleCC \(Self.spacerName)")
        defaults.removeObject(forKey: "NSStatusItem Visible \(Self.spacerName)")
        let folderPosition = defaults.object(forKey: Self.positionKey(Self.folderName)) as? Double ?? 580
        defaults.set(folderPosition + 0.5, forKey: Self.positionKey(Self.spacerName))
        let made = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        made.autosaveName = Self.spacerName
        made.isVisible = true
        return made
    }

    private func applySpacerImage() {
        spacer?.button?.imageScaling = .scaleNone
        // Open, the item has a fixed length of its own: a variable one adds
        // padding around even a tiny image, which showed as a wide gap.
        if isRevealed {
            // Taken out of the bar altogether, so no gap is left beside the folder.
            if let spacer { NSStatusBar.system.removeStatusItem(spacer) }
            spacer = nil
        } else {
            if spacer == nil { spacer = makeSpacer() }
            guard let button = spacer?.button else { return }
            let image = NSImage(size: NSSize(width: Self.hiddenWidth, height: 1), flipped: false) { _ in true }
            image.isTemplate = true
            button.image = image
        }
    }

    /// Our own item's window, found by its title. Status item windows carry
    /// numbers that do not fit a window ID, so the number cannot be used.
    private func ownWindowInfo(titled title: String) -> (bounds: CGRect, onScreen: Bool)? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for entry in list where (entry[kCGWindowLayer as String] as? Int) == Self.barLayer
            && (entry[kCGWindowName as String] as? String) == title {
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            return (bounds, (entry[kCGWindowIsOnscreen as String] as? Bool) == true)
        }
        return nil
    }

    /// After closing, the folder icon must still be on screen, or the menu bar
    /// is too full and closing is undone. With the menu bar auto-hidden there is
    /// nothing to see, so the check waits until it is showing.
    private func verifyFolderStillVisible(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, !self.isRevealed else { return }
            guard let info = self.ownWindowInfo(titled: Self.folderName) else {
                self.undoClose()
                return
            }
            if info.bounds.minY < 0 {
                // The menu bar is hidden right now; look again later.
                if attempt < 8 { self.verifyFolderStillVisible(attempt: attempt + 1) }
                return
            }
            if !info.onScreen { self.undoClose() }
        }
    }

    private func undoClose() {
        closeWasUndone = true
        setRevealed(true)
    }

    // MARK: - Clicks

    @objc private func clicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            // Like a folder: a click opens it, showing its icons right beside
            // it, and another click closes it again.
            closePanel()
            setRevealed(!isRevealed)
        }
    }

    private func showMenu() {
        closePanel()
        let menu = NSMenu()
        let toggle = NSMenuItem(title: isRevealed ? text.hideAgain : text.revealAll,
                                action: #selector(toggleRevealed), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let openNyx = NSMenuItem(title: text.openNyx, action: #selector(openNyxPanel), keyEquivalent: "")
        openNyx.target = self
        menu.insertItem(openNyx, at: 0)
        let off = NSMenuItem(title: text.turnOff, action: #selector(turnOff), keyEquivalent: "")
        off.target = self
        menu.addItem(off)
        guard let button = item?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.minY - 4),
                   in: button)
    }

    @objc private func toggleRevealed() { setRevealed(!isRevealed) }
    @objc private func turnOff() { isEnabled = false }
    @objc private func openNyxPanel() { appDelegate()?.showPopoverFromMenuBarFolder(anchor: item?.button) }

    // MARK: - Panel

    private func openPanel() {
        guard let window = item?.button?.window else { return }
        refreshHiddenItems()
        let items = hiddenItems
        let panel = MenuBarFolderPanel(items: items, emptyText: text.empty,
                                       accessibilityHint: AXIsProcessTrusted() ? nil : text.needsAccessibility,
                                       onSelect: { [weak self] tapped in self?.activate(tapped) },
                                       onRelease: { [weak self] dragged in self?.release(dragged) })
        self.panel = panel
        panel.present(below: window.frame)
        installOutsideClickMonitor()
        if isRevealed { captureImages(ids: items.map(\.id)) }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.closePanel() }
        }
    }

    // MARK: - Finding the hidden icons

    /// Rescans the icons left of the spacer and, with Screen Recording, takes
    /// their pictures. The Nyx panel and the folder's strip both read the result.
    /// Looks again at what is inside, and only does the work of taking
    /// pictures when an icon has been put in or taken out.
    func rescanIfChanged() {
        guard isRunning else { return }
        let found = scanHiddenItems()
        let changed = found.map(\.identity) != hiddenItems.map(\.identity)
        if changed { hiddenItems = found }
        // A picture that could not be taken the first time is tried again.
        let missing = hiddenItems.filter { $0.image == nil }.map(\.id)
        if isRevealed, changed || !missing.isEmpty { captureImages(ids: changed ? found.map(\.id) : missing) }
    }

    func refreshHiddenItems() {
        hiddenItems = scanHiddenItems()
        if isRevealed { captureImages(ids: hiddenItems.map(\.id)) }
    }

    private struct BarWindow {
        let id: CGWindowID
        let pid: pid_t
        let title: String
        let bounds: CGRect
    }

    /// Every menu bar icon that belongs to another app, left to right. macOS
    /// gives all their windows to Control Centre, so only the title says which
    /// are macOS's own.
    private func thirdPartyWindows() -> [BarWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [BarWindow] = []
        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == Self.barLayer,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 4, bounds.height > 4, bounds.minY < 40 else { continue }
            let title = entry[kCGWindowName as String] as? String ?? ""
            if title.hasPrefix("NyxMenuBar") || Self.systemTitles.contains(title) || title.hasPrefix("BentoBox") { continue }
            result.append(BarWindow(id: number, pid: pid, title: title, bounds: bounds))
        }
        return result.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    /// Icons to the left of the spacer, nearest first.
    private func scanHiddenItems() -> [HiddenItem] {
        guard let spacerLeft = spacerFrameOrFolder?.minX else { return [] }
        let controlCentrePID = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
        return thirdPartyWindows()
            .filter { $0.bounds.maxX <= spacerLeft + 1 }
            .sorted { $0.bounds.maxX > $1.bounds.maxX }
            .map { window in
                // Windows belong to Control Centre on recent macOS, so the app
                // behind one is only known when the window is owned by the app.
                let app = window.pid == controlCentrePID ? nil : NSRunningApplication(processIdentifier: window.pid)
                let generic = window.title.hasPrefix("Item-") || window.title.isEmpty
                let identity = Self.identity(pid: window.pid, controlCentrePID: controlCentrePID,
                                             title: window.title, width: window.bounds.width)
                return HiddenItem(id: window.id, pid: window.pid,
                                  name: app?.localizedName ?? (generic ? "Menu bar item" : window.title),
                                  appIcon: app?.icon,
                                  image: imageCache[window.id] ?? PictureStore.load(identity),
                                  identity: identity, symbol: Self.systemSymbols[window.title])
            }
    }

    // MARK: - Dropping an icon onto the folder

    /// Watches for a ⌘-drag in the menu bar. macOS lets the icon be dropped
    /// beside the folder but not inside it, so when the drop lands next to the
    /// folder Nyx finishes the move itself: it drags the icon across the
    /// spacer, then closes the folder.
    private func installDragMonitors() {
        guard dragMonitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return }
            DispatchQueue.main.async { self?.takeDragSnapshot() }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.absorbDroppedIcon() }
        }
        dragMonitors = [down, up].compactMap { $0 }
    }

    private func takeDragSnapshot() {
        guard !isAbsorbing else { return }
        dragSnapshot = Dictionary(thirdPartyWindows().map { ($0.id, $0.bounds.minX) }, uniquingKeysWith: { a, _ in a })
    }

    private func absorbDroppedIcon() {
        guard !isAbsorbing, !dragSnapshot.isEmpty,
              let folder = item?.button?.window?.frame, let spacerFrame = spacerFrameOrFolder else { return }
        defer { dragSnapshot = [:] }
        let moved = thirdPartyWindows().first { window in
            guard let before = dragSnapshot[window.id], abs(before - window.bounds.minX) > 6 else { return false }
            // Landed within a few icons of the folder, and not already inside.
            let nearFolder = window.bounds.maxX > folder.minX - 90 && window.bounds.minX < folder.maxX + 90
            return nearFolder && window.bounds.maxX > spacerFrame.minX
        }
        if let moved { absorb(moved.id) }
    }

    private func absorb(_ windowID: CGWindowID) {
        guard AXIsProcessTrusted() else {
            Permissions.shared.requestAccessibility()
            return
        }
        isAbsorbing = true
        setRevealed(true)
        Task { @MainActor [weak self] in
            await self?.captureImagesNow(ids: [windowID])
            try? await Task.sleep(nanoseconds: 450_000_000)
            self?.performAbsorb(windowID)
        }
    }

    private func performAbsorb(_ windowID: CGWindowID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let from = Self.currentCenter(of: windowID),
                  let spacerFrame = self.spacerFrameOrFolder, spacerFrame.minX > 40 else {
                self.finishAbsorbing(success: false)
                return
            }
            let target = CGPoint(x: spacerFrame.minX - 3, y: from.y)
            DispatchQueue.global(qos: .userInteractive).async {
                Self.commandDrag(from: from, to: target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.finishAbsorbing(success: true) }
            }
        }
    }

    /// Takes an icon back out of the folder: the opposite of dropping it in.
    /// The icon is dragged to just right of the spacer, where it stays visible.
    func release(_ hidden: HiddenItem) {
        guard !isAbsorbing else { return }
        guard AXIsProcessTrusted() else {
            Permissions.shared.requestAccessibility()
            return
        }
        isAbsorbing = true
        closePanel()
        setRevealed(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            guard let from = Self.currentCenter(of: hidden.id),
                  let spacerFrame = self.spacerFrameOrFolder else {
                self.finishAbsorbing(success: false)
                return
            }
            let target = CGPoint(x: spacerFrame.maxX + 10, y: from.y)
            DispatchQueue.global(qos: .userInteractive).async {
                Self.commandDrag(from: from, to: target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.imageCache[hidden.id] = nil
                    self.finishAbsorbing(success: true)
                }
            }
        }
    }

    private func finishAbsorbing(success: Bool) {
        refreshHiddenItems()
        if success, !hiddenItems.isEmpty { setRevealed(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isAbsorbing = false
            if !success { NSSound.beep() }
        }
    }

    /// A ⌘-drag with the mouse, the way a person moves a menu bar icon.
    private static func commandDrag(from start: CGPoint, to end: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let original = CGEvent(source: nil)?.location ?? start
        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        CGWarpMouseCursorPosition(start)
        usleep(60_000)
        post(.leftMouseDown, start)
        usleep(90_000)
        let steps = 24
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            usleep(16_000)
        }
        usleep(80_000)
        post(.leftMouseUp, end)
        usleep(60_000)
        CGWarpMouseCursorPosition(original)
    }

    private func captureImages(ids: [CGWindowID]) {
        Task { @MainActor [weak self] in await self?.captureImagesNow(ids: ids) }
    }

    /// Photographs the given icons, which have to be on screen, and keeps the
    /// pictures for when they are tucked away.
    @MainActor
    private func captureImagesNow(ids: [CGWindowID]) async {
        guard CGPreflightScreenCaptureAccess(), !ids.isEmpty else { return }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            NSLog("NyxFolder: could not list windows for capture")
            return
        }
        let windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var taken = 0
        for id in ids {
            guard let window = windows[id] else {
                NSLog("NyxFolder: window %u is not in the shareable list", id)
                continue
            }
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(window.frame.width * 2))
            configuration.height = max(1, Int(window.frame.height * 2))
            configuration.showsCursor = false
            let image: CGImage
            do {
                image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: window),
                    configuration: configuration)
            } catch {
                NSLog("NyxFolder: capture of window %u failed: %@", id, String(describing: error))
                continue
            }
            let picture = NSImage(cgImage: image, size: NSSize(width: window.frame.width, height: window.frame.height))
            imageCache[id] = picture
            if let identity = hiddenItems.first(where: { $0.id == id })?.identity { PictureStore.save(picture, identity: identity) }
            taken += 1
            panel?.update(id: id, image: picture)
            if let index = hiddenItems.firstIndex(where: { $0.id == id }) { hiddenItems[index].image = picture }
        }
        NSLog("NyxFolder: captured %ld of %ld icons", taken, ids.count)
    }

    // MARK: - Forwarding a click

    /// Opens one icon from inside the folder the way Ice does: only that icon
    /// is moved out, next to the folder, and clicked there. The rest stay
    /// tucked away, and the icon goes back in once its menu is done with.
    func activate(_ hidden: HiddenItem) {
        closePanel()
        guard AXIsProcessTrusted() else {
            Permissions.shared.requestAccessibility()
            return
        }
        guard tempShown == nil, let folder = ownWindow(titled: Self.folderName),
              let owner = Self.ownerPID(of: hidden.id) else {
            NSSound.beep()
            return
        }
        tempShown = (hidden.id, owner)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let start = Self.frame(of: hidden.id)
            Self.post(item: hidden.id, owner: owner, type: .leftMouseDown, at: CGPoint(x: 20_000, y: 20_000), flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(60))
            Self.post(item: folder.id, owner: owner, type: .leftMouseUp, at: CGPoint(x: folder.bounds.minX, y: folder.bounds.midY),
                      flags: .maskCommand)
            // Wait for the icon to arrive beside the folder.
            var arrived: CGRect?
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(50))
                if let now = Self.frame(of: hidden.id), now != start, now.minX >= 0 { arrived = now; break }
            }
            guard let frame = arrived else {
                self.tempShown = nil
                NSSound.beep()
                return
            }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            Self.post(item: hidden.id, owner: owner, type: .leftMouseDown, at: center, flags: [], click: true)
            try? await Task.sleep(for: .milliseconds(40))
            Self.post(item: hidden.id, owner: owner, type: .leftMouseUp, at: center, flags: [], click: true)
            self.scheduleRecollapse()
        }
    }

    /// The icon brought out of the folder for a click, and the app it belongs to.
    private var tempShown: (id: CGWindowID, owner: pid_t)?

    /// Puts the icon brought out for a click back inside the folder.
    private func returnTempShown() {
        guard let shown = tempShown else { return }
        tempShown = nil
        guard let spacer = ownWindow(titled: Self.spacerName) else { return }
        Self.post(item: shown.id, owner: shown.owner, type: .leftMouseDown, at: CGPoint(x: 20_000, y: 20_000), flags: .maskCommand)
        usleep(60_000)
        Self.post(item: spacer.id, owner: shown.owner, type: .leftMouseUp,
                  at: CGPoint(x: spacer.bounds.minX, y: spacer.bounds.midY), flags: .maskCommand)
    }

    private func ownWindow(titled title: String) -> (id: CGWindowID, bounds: CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for entry in list where (entry[kCGWindowLayer as String] as? Int) == Self.barLayer
            && (entry[kCGWindowName as String] as? String) == title {
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            return (id, bounds)
        }
        return nil
    }

    private static func currentCenter(of id: CGWindowID) -> CGPoint? {
        guard let bounds = frame(of: id), bounds.minX >= 0 else { return nil }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private static func frame(of id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let dict = list.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }

    /// The app an icon belongs to. macOS hands the windows to Control Centre,
    /// so the owner is found through Accessibility, by where its icon sits.
    private static func ownerPID(of id: CGWindowID) -> pid_t? {
        guard let frame = frame(of: id) else { return nil }
        for app in NSWorkspace.shared.runningApplications {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &bar) == .success,
                  let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
            for child in (children as? [AXUIElement]) ?? [] {
                var value: CFTypeRef?
                var point = CGPoint.zero
                guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &value) == .success,
                      let value, AXValueGetValue(value as! AXValue, .cgPoint, &point) else { continue }
                if abs(point.x - frame.minX) <= 3 { return app.processIdentifier }
            }
        }
        return nil
    }

    /// An event aimed at one menu bar icon's window rather than at the pointer,
    /// so it reaches the icon wherever it is, on screen or not.
    private static func post(item: CGWindowID, owner: pid_t, type: CGEventType, at point: CGPoint,
                             flags: CGEventFlags, click: Bool = false) {
        if let combined = CGEventSource(stateID: .combinedSessionState) {
            let permit: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
            combined.setLocalEventsFilterDuringSuppressionState(permit, state: .eventSuppressionStateRemoteMouseDrag)
            combined.setLocalEventsFilterDuringSuppressionState(permit, state: .eventSuppressionStateSuppressionInterval)
            combined.localEventsSuppressionInterval = 0
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        else { return }
        let window = Int64(item)
        event.flags = flags
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(owner))
        event.setIntegerValueField(.eventSourceUserData, value: Int64.random(in: 1...Int64.max))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: window)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: window)
        if let windowField = CGEventField(rawValue: 0x33) { event.setIntegerValueField(windowField, value: window) }
        if click { event.setIntegerValueField(.mouseEventClickState, value: 1) }
        let cursor = CGEvent(source: nil)?.location
        event.postToPid(owner)
        event.post(tap: .cgSessionEventTap)
        if let cursor { CGWarpMouseCursorPosition(cursor) }
    }

    /// The icon's menu is the app's own, so wait for the next click or key
    /// anywhere (or a timeout) before putting the icons away.
    private func scheduleRecollapse() {
        cancelRecollapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.tempShown != nil || self.isRevealed else { return }
            self.recollapseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
                self?.recollapseSoon()
            }
            self.recollapseTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                self?.recollapseSoon()
            }
        }
    }

    private func recollapseSoon() {
        cancelRecollapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            if self.tempShown != nil { self.returnTempShown() } else { self.setRevealed(false) }
        }
    }

    private func cancelRecollapse() {
        if let recollapseMonitor { NSEvent.removeMonitor(recollapseMonitor) }
        recollapseMonitor = nil
        recollapseTimer?.invalidate()
        recollapseTimer = nil
    }
}
