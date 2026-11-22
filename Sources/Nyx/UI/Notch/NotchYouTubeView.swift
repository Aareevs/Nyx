import SwiftUI

/// The music page's playlists: Spotify's from the account, or YouTube and
/// YouTube Music playlists saved here by their links.
struct NotchPlaylistsView: View {
    @AppStorage(DefaultsKey.notchPlaylistsSource) private var source = NotchPlaylistsSource.spotify.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(NotchPlaylistsSource.allCases) { option in
                    Button { source = option.rawValue } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(source == option.rawValue ? 1 : 0.55))
                            .padding(.horizontal, 10).frame(height: 22)
                            .background(Capsule().fill(.white.opacity(source == option.rawValue ? 0.16 : 0)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(source == option.rawValue ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            if NotchPlaylistsSource(rawValue: source) == .youtube { NotchYouTubeView() } else { NotchSpotifyView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

enum NotchPlaylistsSource: String, CaseIterable, Identifiable {
    case spotify, youtube
    var id: String { rawValue }
    var title: String { self == .spotify ? "Spotify" : "YouTube" }
}

/// YouTube and YouTube Music playlists saved by their links; a song opens in
/// the browser, where the island's player picks it up.
struct NotchYouTubeView: View {
    @ObservedObject private var library = YouTubeLibrary.shared
    @ObservedObject private var player = YouTubeInlinePlayer.shared
    @ObservedObject private var account = YouTubeAccount.shared
    @State private var open: YouTubeSavedPlaylist?
    @State private var adding = false
    @State private var link = ""
    @State private var arranging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let message = library.message {
                Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if adding { addRow }
            if let open {
                list(library.videos.map { video in
                    Row(id: video.id, title: video.title, subtitle: video.artist,
                        image: YouTubePlaylistSupport.thumbnail(video.id), active: player.current?.id == video.id) {
                        library.play(video, in: open)
                    }
                })
            } else if library.playlists.isEmpty, !adding {
                NotchEmptyView(symbol: "play.rectangle", message: "Paste a YouTube or YouTube Music playlist link to keep it here. Public and unlisted playlists work.") {
                    NotchPillButton(title: "Paste link", prominent: true) { pasteAndAdd() }
                }
            } else {
                let playlists = library.playlists
                list(playlists.enumerated().map { index, playlist in
                    Row(id: playlist.id, title: playlist.title,
                        subtitle: (playlist.music ? "YouTube Music" : "YouTube") + " · \(playlist.count) songs",
                        image: playlist.firstVideo.flatMap(YouTubePlaylistSupport.thumbnail), active: false,
                        move: arranging ? { library.move(playlist, by: $0) } : nil,
                        remove: arranging ? { library.remove(playlist) } : nil,
                        canMoveUp: index > 0, canMoveDown: index < playlists.count - 1) {
                        guard !arranging else { return }
                        self.open = playlist
                        Task { await library.loadVideos(of: playlist) }
                    }
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear { library.clearMessage() }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            if let open {
                Button { self.open = nil; library.clearMessage() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24).contentShape(Circle())
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 12)).accessibilityLabel("Back to playlists")
                Text(open.title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                if library.loading { ProgressView().controlSize(.mini) }
                NotchPillButton(title: "Play", prominent: true) { library.play(nil, in: open) }
            } else {
                Text("Your playlists").font(.callout.weight(.semibold))
                Spacer()
                if library.loading { ProgressView().controlSize(.mini) }
                NotchMenuButton(title: "YouTube account", items: account.signedIn
                    ? [NotchMenuItem(title: "Signed in to YouTube", checked: true) {},
                       NotchMenuItem(title: "Sign out") { account.signOut() }]
                    : [NotchMenuItem(title: "Sign in to YouTube (optional, for Premium)") { account.openSignIn() }]) {
                    Image(systemName: account.signedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(account.signedIn ? Color.green : .primary)
                        .frame(width: 24, height: 24).contentShape(Circle())
                }
                .help(account.signedIn ? "Signed in to YouTube" : "Sign in to YouTube (optional)")
                if !library.playlists.isEmpty {
                    Button { arranging.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                        .buttonStyle(.borderless).foregroundStyle(arranging ? Color.green : .primary)
                        .help(arranging ? "Done" : "Arrange or remove playlists")
                        .accessibilityLabel(arranging ? "Done" : "Arrange or remove playlists")
                }
                Button { adding.toggle(); link = ""; library.clearMessage() } label: { Image(systemName: adding ? "xmark" : "plus") }
                    .buttonStyle(.borderless).help(adding ? "Cancel" : "Add a playlist")
                    .accessibilityLabel(adding ? "Cancel" : "Add a playlist")
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            TextField("Playlist link", text: $link)
                .textFieldStyle(.roundedBorder).controlSize(.small)
                .onSubmit { add(link) }
            NotchPillButton(title: "Paste") { pasteAndAdd() }
            NotchPillButton(title: "Add", prominent: true) { add(link) }
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || library.loading)
        }
    }

    private func pasteAndAdd() {
        GeneralPasteboardAccess.shared.async({ NSPasteboard.general.string(forType: .string) }) { copied in
            link = copied ?? ""
            adding = true
            add(link)
        }
    }

    private func add(_ text: String) {
        Task {
            if await library.add(link: text) { link = ""; adding = false }
        }
    }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let image: URL?
        let active: Bool
        var move: ((Int) -> Void)? = nil
        var remove: (() -> Void)? = nil
        var canMoveUp = false
        var canMoveDown = false
        let action: () -> Void
    }

    private func small(_ symbol: String, _ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26).contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 13))
        .disabled(!enabled).opacity(enabled ? 1 : 0.3)
        .help(label).accessibilityLabel(label)
    }

    private func list(_ rows: [Row]) -> some View {
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
                                .frame(width: 48, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title).font(.callout.weight(.medium)).lineLimit(1)
                                        .foregroundStyle(row.active ? Color.red : .primary)
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
                            small("chevron.up", "Move up", enabled: row.canMoveUp) { move(-1) }
                            small("chevron.down", "Move down", enabled: row.canMoveDown) { move(1) }
                        }
                        if let remove = row.remove { small("trash", "Remove playlist", action: remove) }
                    }
                }
            }
        }
        .notchScrollEdgeFade()
    }
}
