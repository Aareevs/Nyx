import AppKit

/// AppKit describes a non-activating panel as a system dialog, which tiling
/// window managers track and list on whichever space is current. The shared
/// panel class is compiled here and created deferred, so no window is shown;
/// each floating surface's own file is read for the class it builds.
enum OverlayPanelTests {
    static func run(_ suite: TestSuite) {
        // The Clipboard History window keeps a title bar strip to drag it by.
        for style: NSWindow.StyleMask in [[.borderless, .nonactivatingPanel],
                                          [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]] {
            let overlay = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                                       styleMask: style, backing: .buffered, defer: true)
            suite.expect(overlay.accessibilitySubrole() == .unknown,
                         "a floating overlay describes itself as an undescribed window, so window managers skip it")
            suite.expect(overlay.accessibilityRole() == .window && overlay.isAccessibilityElement(),
                         "a floating overlay stays an accessible window for assistive technology")
        }

        // HUDs, previews, pickers and the menu's positioning helper: none is a
        // document window, and each floats over other apps' windows.
        let surfaces = [
            "Sources/Nyx/App/AppDelegate.swift",
            "Sources/Nyx/UI/PermissionGuideOverlay.swift",
            "Sources/Nyx/UI/QuitProtection/QuitProtectionHUD.swift",
            "Sources/Nyx/Services/QuickTools/QuickToolHUD.swift",
            "Sources/Nyx/Services/QuickTools/QuickLauncherService.swift",
            "Sources/Nyx/Services/QuickTools/CameraPreviewService.swift",
            "Sources/Nyx/Services/QuickTools/RecentCaptureService.swift",
            "Sources/Nyx/Services/QuickTools/ScreenshotSelectionController.swift",
            "Sources/Nyx/Services/QuickTools/ScreenshotQuickPreviewController.swift",
            "Sources/Nyx/Services/QuickTools/ScreenshotPinController.swift",
            "Sources/Nyx/Services/QuickTools/QRResultController.swift",
            "Sources/Nyx/Services/QuickTools/ScratchpadService.swift",
            "Sources/Nyx/Services/Snippets/SnippetLibraryService.swift",
            "Sources/Nyx/Services/Clipboard/ClipboardHistoryService.swift",
            "Sources/Nyx/Services/CommandBar/CommandBarService.swift",
            "Sources/Nyx/Services/Switcher/AppSwitcher.swift",
            "Sources/Nyx/Services/RadialMenu/RadialMenuService.swift",
            "Sources/Nyx/Services/RadialMenu/RadialNowPlayingService.swift",
            "Sources/Nyx/Services/DockPreview/DockPreviewService.swift",
            "Sources/Nyx/Services/WindowLayout/WindowLayoutService.swift",
            "Sources/Nyx/Services/Finder/FinderCutPaste.swift",
            "Sources/Nyx/Services/Display/BrightnessOSD.swift",
            "Sources/Nyx/Services/CleaningMode/CleaningModeManager.swift",
            "Sources/Nyx/Services/Recorder/RecorderIndicator.swift",
        ]
        for path in surfaces {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(source.range(of: #"\bOverlayPanel\(contentRect|:\s*OverlayPanel\b"#,
                                      options: .regularExpression) != nil
                         && !source.contains("NSPanel(contentRect")
                         && source.range(of: #"class \w+:\s*NSPanel\b"#, options: .regularExpression) == nil,
                         "\(path) builds its floating panels as overlays, which window managers do not list")
        }
    }
}
