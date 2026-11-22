import AppKit
import SwiftUI

/// A key field holds one line, so pasting a code snippet into it keeps the first
/// line and drops the rest, key included. While the field has the keyboard,
/// command-V reads the clipboard itself and hands over the key found in it.
private struct ChatKeyPaste: ViewModifier {
    let active: Bool
    let onText: (String) -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onChange(of: active) { _, now in now ? install() : remove() }
            .onAppear { if active { install() } }
            .onDisappear { remove() }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v",
                  let copied = NSPasteboard.general.string(forType: .string),
                  // Only what holds more than one line needs this; one line pastes as usual.
                  copied.contains(where: \.isNewline) else { return event }
            onText(copied)
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    /// Multi-line text pasted while `active` goes to `onText` whole, instead of
    /// into the focused field, which would keep one line.
    func chatKeyPaste(active: Bool, _ onText: @escaping (String) -> Void) -> some View {
        modifier(ChatKeyPaste(active: active, onText: onText))
    }
}
