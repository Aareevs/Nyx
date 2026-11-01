import SwiftUI

/// The user's Spotify playlists and their songs, to choose from without
/// leaving the island.
struct NotchSpotifyView: View {
    @ObservedObject private var auth = SpotifyAuth.shared
    @ObservedObject private var library = SpotifyLibrary.shared
    @State private var open: SpotifyPlaylist?
    @State private var playingID: String?
    @State private var arranging = false

    var body: some View {
        Group {
            switch auth.state {
            case .connected: connected
            case .connecting:
                NotchEmptyView(symbol: "music.note.list", message: "Finish signing in to Spotify in your browser") {
                    ProgressView().controlSize(.small)
                }
            case .disconnected, .failed:
                NotchEmptyView(symbol: "music.note.list", message: failure ?? "See your Spotify playlists and pick a song here") {
                    NotchPillButton(title: "Connect Spotify", prominent: true) { auth.connect() }
                }
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: auth.isConnected) { await library.loadPlaylists() }
    }

    private var failure: String? {
        if case .failed(let reason) = auth.state { return reason }
        return nil
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let open {
                    Button { self.open = nil } label: {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24).contentShape(Circle())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 12)).accessibilityLabel("Back to playlists")
                    Text(open.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Spacer()
                    NotchPillButton(title: "Play", prominent: true) { Task { await library.play(nil, in: open) } }
                } else {
                    Text("Your playlists").font(.callout.weight(.semibold))
                    Spacer()
                }
                if library.loading { ProgressView().controlSize(.mini) }
                if open == nil {
                    Button { arranging.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                        .buttonStyle(.borderless).foregroundStyle(arranging ? Color.green : .primary)
                        .help(arranging ? "Done arranging" : "Arrange playlists")
                        .accessibilityLabel(arranging ? "Done arranging" : "Arrange playlists")
                    Button { Task { await library.loadPlaylists(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).disabled(library.loading).help("Refresh").accessibilityLabel("Refresh")
                    Button { auth.disconnect() } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(.borderless).help("Disconnect Spotify").accessibilityLabel("Disconnect Spotify")
                }
            }
            if let message = library.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if let open {
                list(rows: library.tracks.map { track in
                    Row(id: track.id, title: track.name, subtitle: track.artist, image: track.imageURL,
                        active: playingID == track.id) {
                        playingID = track.id
                        Task { await library.play(track, in: open) }
                    }
                })
            } else {
                let playlists = library.orderedPlaylists
                list(rows: playlists.enumerated().map { index, playlist in
                    Row(id: playlist.id, title: playlist.name,
                        subtitle: playlist.trackCount > 0 ? "\(playlist.trackCount) songs" : playlist.owner,
                        image: playlist.imageURL, active: false,
                        move: arranging ? { library.move(playlist, by: $0) } : nil,
                        canMoveUp: index > 0, canMoveDown: index < playlists.count - 1) {
                        guard !arranging else { return }
                        self.open = playlist
                        Task { await library.loadTracks(of: playlist) }
                    }
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let image: URL?
        let active: Bool
        /// Set while arranging: moves the row up (-1) or down (1).
        var move: ((Int) -> Void)? = nil
        var canMoveUp = false
        var canMoveDown = false
        let action: () -> Void
    }

    private func arrow(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26).contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 13))
        .disabled(!enabled).opacity(enabled ? 1 : 0.3)
        .help(label).accessibilityLabel(label)
    }

    private func list(rows: [Row]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                    Button(action: row.action) {
                        HStack(spacing: 10) {
                            AsyncImage(url: row.image) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.white.opacity(0.08)
                            }
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title).font(.callout.weight(.medium)).lineLimit(1)
                                    .foregroundStyle(row.active ? Color.green : .primary)
                                if !row.subtitle.isEmpty {
                                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let move = row.move {
                        arrow("chevron.up", "Move up", enabled: row.canMoveUp) { move(-1) }
                        arrow("chevron.down", "Move down", enabled: row.canMoveDown) { move(1) }
                    }
                    }
                }
            }
        }
        .notchScrollEdgeFade()
    }
}
