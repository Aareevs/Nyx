import SwiftUI

/// Accounts Nyx can sign in to. Each one unlocks something in the island.
struct ConnectorsSettings: View {
    @ObservedObject private var spotify = SpotifyAuth.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Connectors").font(.title2.bold())
                card
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
    }

    private var card: some View {
            SettingsCard {
                SettingsRow(symbol: "music.note.list", title: "Spotify",
                            caption: "Browse your playlists and pick a song from the Dynamic Island. Choosing songs needs Spotify Premium.") {
                    switch spotify.state {
                    case .connected:
                        Button("Disconnect") { spotify.disconnect() }
                    case .connecting:
                        ProgressView().controlSize(.small)
                    case .disconnected, .failed:
                        Button("Connect") { spotify.connect() }
                    }
                }
                if case .connected = spotify.state {
                    Text("Connected. Open the playlist button on the island's Music page.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if case .connecting = spotify.state {
                    Text("Finish signing in to Spotify in your browser.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if case .failed(let reason) = spotify.state {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
            }
    }
}
