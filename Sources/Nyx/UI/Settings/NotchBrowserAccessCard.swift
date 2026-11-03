import AppKit
import SwiftUI

/// Lets a person grant the one permission the browser icons need, without
/// hunting through System Settings: a button asks every open browser, and a
/// row per browser says where it stands.
struct NotchBrowserAccessCard: View {
    @State private var browsers: [NotchSiteIcon.BrowserAccess] = []

    var body: some View {
        SettingsCard(title: "Browser access") {
            SettingsRow(symbol: "safari", title: "Site icons for browser media",
                        caption: "X, Reddit, Instagram, Netflix, JioHotstar and LinkedIn show their own icon on the island. For that Nyx asks your browser which tab is playing, and macOS wants your OK for each browser.") {
                Button("Allow") {
                    DispatchQueue.global(qos: .userInitiated).async {
                        NotchSiteIcon.requestBrowserAccess()
                        let updated = NotchSiteIcon.browserAccess()
                        DispatchQueue.main.async { browsers = updated }
                    }
                }
            }
            ForEach(browsers) { browser in
                SettingsRow(symbol: nil, title: browser.name) {
                    Label(browser.allowed ? "Allowed" : "Not allowed yet",
                          systemImage: browser.allowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(browser.allowed ? Color.green : Color.orange)
                        .font(.callout)
                }
            }
            if browsers.isEmpty {
                Text("Open a browser, then press Allow.").font(.caption).foregroundStyle(.secondary)
            } else if browsers.contains(where: { !$0.allowed }) {
                HStack {
                    Text("Denied it before? Turn Nyx on under Automation in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .onAppear { browsers = NotchSiteIcon.browserAccess() }
    }
}
