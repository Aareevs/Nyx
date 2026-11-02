import AppKit
import SwiftUI

private struct NotchFlatTilesKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Home's shortcuts draw as a bare glyph over a small label, with no
    /// circle until a tile is on.
    var notchFlatTiles: Bool {
        get { self[NotchFlatTilesKey.self] }
        set { self[NotchFlatTilesKey.self] = newValue }
    }
}

/// One line of text that scrolls round when it does not fit: out of one side,
/// back in from the other, with a pause at the start. A title that fits
/// stays still, and with Reduce Motion it is cut off at the end instead.
struct NotchMarqueeText: View {
    let text: String
    let font: Font
    private let gap: CGFloat = 32
    private let speed: Double = 28
    private let pause: Double = 2
    @State private var textWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A hidden line gives the view its height and takes only the room it is
        // given; the full width of the text is measured off to the side, so a
        // long title never widens its column.
        Text(text).font(font).lineLimit(1).hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                Text(text).font(font).lineLimit(1).fixedSize().hidden()
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { textWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, width in textWidth = width }
                    })
            }
            .overlay {
                GeometryReader { geometry in
                    if textWidth > geometry.size.width + 0.5, !reduceMotion {
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                            let period = Double(textWidth + gap) / speed
                            let phase = context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: period + pause)
                            let offset = phase < pause ? 0 : -CGFloat((phase - pause) * speed)
                            HStack(spacing: gap) { label; label }
                                .offset(x: offset)
                                .frame(width: geometry.size.width, alignment: .leading)
                        }
                        .clipped()
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: 0.9),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                    } else {
                        label.frame(width: geometry.size.width, alignment: .leading)
                    }
                }
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
    }
}

/// Home's row: the player and the day side by side, sized from the room the
/// row really has, not from the page's nominal width.
struct NotchHomeRow: View {
    @ObservedObject var notch: NotchService
    var height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 14
            let day = (geometry.size.width * 0.42).rounded()
            let player = max(0, geometry.size.width - day - 1 - 2 * gap)
            HStack(spacing: gap) {
                NotchHomeMusic(notch: notch, height: height, width: player).frame(width: player)
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1).padding(.vertical, 4)
                NotchHomeCalendar(service: notch, height: height, width: day).frame(width: day)
            }
            .frame(width: geometry.size.width, height: height, alignment: .leading)
        }
        .frame(height: height)
    }
}

/// Home's player: the cover as tall as the row with the app it plays in on
/// its corner, the song at its top and the transport at its foot.
struct NotchHomeMusic: View {
    @ObservedObject var notch: NotchService
    var height: CGFloat
    /// The panel's own width; the type scales with it, never below a readable size.
    var width: CGFloat
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var isIdle: Bool { !preview && music.playback == nil && !music.awaitingPlayback }
    private var k: CGFloat { min(1, max(0.7, width / 322)) }

    var body: some View {
        // The cover takes what the song and the buttons leave: at least 112 points for them.
        let gap = 20 * k
        let art = min(height, 128 * k, max(60, width - gap - 118))
        let textWidth = max(80, width - art * 1.06 - gap)
        let buttons = min(1, max(0.7, textWidth / 132))
        let player = isIdle ? NotchPreferredPlayer.current() : nil
        let idleOpens = player != nil
        let openTitle = player.map { NotchPreferredPlayer.openTitle(for: $0) } ?? ""
        let track = music.playback?.track
        HStack(spacing: gap) {
            // With nothing playing, the cover opens the music app instead.
            Button {
                if isIdle, NotchPreferredPlayer.open() { return }
                notch.select(.music)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    NotchArtwork(image: music.artwork, size: art, source: track)
                    if let icon = track.flatMap(RadialNowPlayingApplication.icon(for:)) {
                        Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                            .frame(width: art * 0.3, height: art * 0.3)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .offset(x: art * 0.06, y: art * 0.06)
                    }
                }
                .padding(.trailing, art * 0.06).padding(.bottom, art * 0.06)
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 16))
            .accessibilityLabel(idleOpens ? openTitle : text.mediaNowPlaying)
            .help(idleOpens ? openTitle : text.mediaNowPlaying)
            VStack(alignment: .leading, spacing: 0) {
                Button { notch.select(.music) } label: { titles(track) }.buttonStyle(.plain)
                Spacer(minLength: 2)
                if let playback = music.playback {
                    NotchMusicTransport(playback: playback, compact: true)
                        .scaleEffect(buttons, anchor: .leading)
                        .frame(width: 132 * buttons, height: 36 * buttons, alignment: .leading)
                } else if idleOpens {
                    NotchMusicIdleTransport(compact: true, openTitle: openTitle)
                        .scaleEffect(buttons, anchor: .leading)
                        .frame(width: 132 * buttons, height: 36 * buttons, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: art)
        }
        .frame(width: width, alignment: .leading)
        .frame(height: height, alignment: .top)
        .onAppear { if !preview { music.refreshAutomation() } }
    }

    private func titles(_ track: RadialNowPlayingSnapshot?) -> some View {
        let idleLine = music.awaitingPlayback ? "" : FeatureStrings.notch(l10n.language).musicHint
        return VStack(alignment: .leading, spacing: 2) {
            NotchMarqueeText(text: track?.title ?? (music.awaitingPlayback ? text.mediaNowPlaying : text.mediaNothingPlaying),
                             font: .system(size: max(14, 18 * k), weight: .bold))
            if music.commandFailed {
                Text(FeatureStrings.notchMusicExtras(l10n.language).playbackFailed)
                    .font(.system(size: 12)).foregroundStyle(.orange).lineLimit(1)
            } else if let track {
                // A single's album is its title: say it once.
                if let album = track.album, !album.isEmpty,
                   album.caseInsensitiveCompare(track.title ?? "") != .orderedSame {
                    Text(album).font(.system(size: max(12, 14 * k))).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                if let artist = track.artist, !artist.isEmpty {
                    Text(artist).font(.system(size: max(12.5, 14 * k))).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            } else if !idleLine.isEmpty {
                Text(idleLine).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Home's day: the month and the days around today, centred with today
/// large and red, then what is on today as a block below.
struct NotchHomeCalendar: View {
    let service: NotchService
    var height: CGFloat
    var width: CGFloat
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var k: CGFloat { min(1, max(0.62, width / 300)) }

    var body: some View {
        TimelineView(.everyMinute) { context in content(now: context.date) }
    }

    private func content(now: Date) -> some View {
        let events = Self.todayEvents(calendar.events, now: now)
        return Button { service.select(.calendar) } label: {
            VStack(spacing: events.isEmpty ? 14 * k : 10 * k) {
                header(now: now)
                if events.isEmpty { empty } else { rows(events) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: height)
    }

    /// What is still on today, soonest first: events that have not ended yet.
    static func todayEvents(_ events: [NotchCalendarEvent], now: Date, calendar: Calendar = .current) -> [NotchCalendarEvent] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return Array(NotchCalendarSupport.ordered(events)
            .filter { $0.start < end && $0.end > start && $0.end > now }.prefix(2))
    }

    private func header(now: Date) -> some View {
        ViewThatFits(in: .horizontal) {
            days(now: now, spread: 2)
            days(now: now, spread: 1)
            days(now: now, spread: 0)
        }
    }

    private func days(now: Date, spread: Int) -> some View {
        let locale = l10n.language.formattingLocale()
        let calendar = Calendar.current
        var month = Date.FormatStyle.dateTime.month(.abbreviated); month.locale = locale
        var weekday = Date.FormatStyle.dateTime.weekday(.abbreviated); weekday.locale = locale
        var number = Date.FormatStyle.dateTime.day(.twoDigits); number.locale = locale
        return HStack(alignment: .bottom, spacing: 11 * k) {
            Text(now.formatted(month)).font(.system(size: 34 * k, weight: .bold)).fixedSize()
                .offset(x: -9 * k)
            HStack(spacing: 10 * k) {
                ForEach(-spread...spread, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
                    VStack(spacing: 1) {
                        Text(offset == 0 ? day.formatted(weekday).uppercased() : " ")
                            .font(.system(size: max(9, 11 * k), weight: .bold)).foregroundStyle(.red).fixedSize()
                        Text(day.formatted(number))
                            .font(.system(size: (offset == 0 ? 34 : 19) * k, weight: offset == 0 ? .bold : .regular))
                            .foregroundStyle(offset == 0 ? Color.red : .white.opacity(0.55)).fixedSize()
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "calendar.badge.checkmark").font(.system(size: 24 * k)).foregroundStyle(.white.opacity(0.32))
            Text(NotchCalendarSupport.isEnabled() ? text.nothingToday : text.calendarOff)
                .font(.system(size: max(12, 16 * k))).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
        }
    }

    private func rows(_ events: [NotchCalendarEvent]) -> some View {
        VStack(spacing: 8 * k) {
            ForEach(events) { event in
                HStack(spacing: 9) {
                    Capsule().fill(Color(red: event.color.red, green: event.color.green, blue: event.color.blue))
                        .frame(width: 3, height: max(24, 30 * k))
                    VStack(alignment: .leading, spacing: 1) {
                        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(title.isEmpty ? FeatureStrings.notchCalendar(l10n.language).untitled : title)
                            .font(.system(size: max(12.5, 15 * k), weight: .semibold)).lineLimit(1)
                        Text(timeText(event)).font(.system(size: max(10.5, 12 * k))).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, width * 0.14)
    }

    private func timeText(_ event: NotchCalendarEvent) -> String {
        if event.allDay { return FeatureStrings.notchCalendar(l10n.language).allDay }
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.locale = l10n.language.formattingLocale()
        return event.start.formatted(style) + " – " + event.end.formatted(style)
    }
}
