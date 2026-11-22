import AppKit
import SwiftUI

/// What changed in this version, shown once after an update and available
/// again from Settings → General → Updates.
struct WhatsNewView: View {
    let version: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text("What's new in Nyx \(version)")
                    .font(.title2.weight(.semibold))
                Text("Here are the biggest changes in this update.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 28).padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(WhatsNewInfo.items(for: version)) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.headline)
                            Text(item.text)
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 32)

            HStack {
                Button("See all changes") { NSWorkspace.shared.open(WhatsNewInfo.releaseURL(for: version)) }
                Spacer()
                Button("Continue", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 24)
        }
        .frame(width: 480)
    }
}
