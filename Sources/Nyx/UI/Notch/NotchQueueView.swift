import SwiftUI

struct NotchQueueView: View {
    let playback: NotchPlayback
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchMusicExtrasStrings { FeatureStrings.notchMusicExtras(l10n.language) }

    private var emptyMessage: String {
        switch service.queueNote {
        case .needsOnline: return text.queueNeedsOnline
        case .needsSpotifyLogin: return text.queueNeedsSpotify
        case .needsBrowserScripting: return text.queueNeedsScripting
        case .noPlaylist: return text.queueNoPlaylist
        case .unavailable: return text.queueWebFailed
        case nil: return service.upcoming == nil ? text.queueUnavailable : text.queueEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.queue).font(.callout.weight(.semibold))
                Spacer()
                if service.queueLoading || service.queueActionPending { ProgressView().controlSize(.mini) }
                Button { service.refreshQueue() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(service.queueLoading || service.queueActionPending)
                    .help(text.refresh).accessibilityLabel(text.refresh)
            }
            if service.queueActionFailed {
                Text(text.actionFailed).font(.caption).foregroundStyle(.orange)
            }
            if let queue = service.upcoming, !service.upcomingRows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Five at a time: as one plays, the sixth moves up to fifth.
                        ForEach(Array(service.upcomingRows.prefix(5))) { item in
                            HStack(spacing: 10) {
                                NotchArtwork(image: service.upcomingArtwork[item.id], size: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                                    if !item.artist.isEmpty { Text(item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if queue.canPlay {
                                    Button { service.playQueued(item) } label: {
                                        Image(systemName: "play.fill").font(.system(size: 11))
                                            .frame(width: 28, height: 28).contentShape(Circle())
                                    }
                                    .buttonStyle(NotchButtonStyle(cornerRadius: 14))
                                    .disabled(service.queueActionPending || service.upcomingIsHeld)
                                    .help(text.playNow).accessibilityLabel("\(text.playNow): \(item.title)")
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                }
                .notchScrollEdgeFade()
            } else if !service.queueLoading {
                NotchEmptyView(symbol: "list.bullet", message: emptyMessage) {
                    switch service.queueNote {
                    case .needsOnline:
                        NotchPillButton(title: text.queueTurnOn, prominent: true) {
                            UserDefaults.standard.set(true, forKey: DefaultsKey.notchQueueOnline)
                            service.refreshQueue()
                        }
                    case .needsBrowserScripting:
                        NotchPillButton(title: text.retry, prominent: true) { service.refreshQueue() }
                    case .needsSpotifyLogin:
                        NotchPillButton(title: text.queueSignIn, prominent: true) {
                            SpotifyAuth.shared.disconnect()
                            SpotifyAuth.shared.connect()
                        }
                    default:
                        NotchPillButton(title: text.openPlayer, prominent: true) { RadialNowPlayingApplication.open(playback.track) }
                    }
                }
            }
        }
        // The title sits as far below the player as the first verse would.
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
