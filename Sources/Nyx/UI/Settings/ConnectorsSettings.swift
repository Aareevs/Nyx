import SwiftUI

/// Accounts Nyx can sign in to. Each one unlocks something in the island.
struct ConnectorsSettings: View {
    @ObservedObject private var spotify = SpotifyAuth.shared

    private var connected: Bool {
        if case .connected = spotify.state { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Connectors").font(.title2.bold())
                    Text("Accounts Nyx can sign in to. Each one unlocks something in the island.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                SettingsCard(title: connected ? "Connected" : "Available") { spotifyRow }
                SettingsCard(title: "More to come") { placeholder }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
    }

    private var spotifyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                logo
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Spotify").font(.system(size: 15, weight: .semibold))
                        if connected {
                            Text("Connected")
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.green)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                        }
                    }
                    Text("Browse your playlists and pick a song from the Dynamic Island. Choosing songs needs Spotify Premium.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 14)
                action
            }
            status.padding(.leading, 60)
        }
    }

    /// Spotify's mark, shipped with the app so it shows on any Mac.
    @ViewBuilder private var logo: some View {
        if let image = NotchStreakLogo.image("connector-spotify") {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(width: 46, height: 46).accessibilityHidden(true)
        } else {
            Image(systemName: "music.note.list").font(.system(size: 20))
                .frame(width: 46, height: 46).accessibilityHidden(true)
        }
    }

    @ViewBuilder private var action: some View {
        switch spotify.state {
        case .connected:
            Button("Disconnect") { spotify.disconnect() }
        case .connecting:
            ProgressView().controlSize(.small)
        case .disconnected, .failed:
            Button("Connect") { spotify.connect() }.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private var status: some View {
        switch spotify.state {
        case .connected:
            Label("Open the playlist button on the island's Music page.", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.secondary).labelStyle(ConnectorStatusLabelStyle(tint: .green))
        case .connecting:
            Text("Finish signing in to Spotify in your browser.").font(.caption).foregroundStyle(.secondary)
        case .failed(let reason):
            Text(reason).font(.caption).foregroundStyle(.orange)
        case .disconnected:
            EmptyView()
        }
    }

    private var placeholder: some View {
        HStack(spacing: 14) {
            Image(systemName: "plus").font(.system(size: 16)).foregroundStyle(.secondary)
                .frame(width: 46, height: 46)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("More connectors").font(.system(size: 14, weight: .semibold))
                Text("Other services will show up here once they are added.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// A status line with its mark in one colour and its words in another.
private struct ConnectorStatusLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
