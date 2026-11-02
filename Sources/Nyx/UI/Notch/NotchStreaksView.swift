import SwiftUI
import AppKit

/// The logos ship in Resources/Images and only label the services they belong to.
enum NotchStreakLogo {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(_ resource: String) -> NSImage? {
        if let cached = cache.object(forKey: resource as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png", subdirectory: "Images"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: resource as NSString)
        return image
    }
}

extension NotchStreakProvider {
    /// The colour of the service's mark: GitHub's grey, LeetCode's amber, Reddit's orange-red.
    var rimColor: Color {
        switch self {
        case .github: return Color(red: 0.80, green: 0.83, blue: 0.88)
        case .leetcode: return Color(red: 1.0, green: 0.63, blue: 0.09)
        case .reddit: return Color(red: 1.0, green: 0.27, blue: 0.0)
        }
    }
}

/// The island's outline, pulsing in a colour while a streak is celebrated.
struct NotchRimPulse: View {
    let contour: Path
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        NotchBackdropShape(contour: contour)
            .stroke(color.opacity(lit ? 1 : 0.35), lineWidth: 2.5)
            .shadow(color: color.opacity(lit ? 0.95 : 0.15), radius: lit ? 11 : 2)
            .onAppear {
                guard !reduceMotion else { lit = true; return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { lit = true }
            }
    }
}

/// A flame that swells and glows, for a streak on the closed island.
struct NotchStreakFlame: View {
    var size: CGFloat = 13
    var animates = true
    @State private var lit = false

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            .scaleEffect(lit ? 1.18 : 0.92)
            .shadow(color: .orange.opacity(lit ? 0.9 : 0.25), radius: lit ? 6 : 1)
            .onAppear {
                guard animates else { lit = true; return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { lit = true }
            }
            .accessibilityHidden(true)
    }
}

struct NotchStreaksView: View {
    let size: CGSize
    @Environment(\.notchSettingsPreview) private var preview
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NotchStreakService.shared
    @AppStorage(DefaultsKey.notchStreakGitHub) private var github = ""
    @AppStorage(DefaultsKey.notchStreakLeetCode) private var leetcode = ""
    @AppStorage(DefaultsKey.notchStreakReddit) private var reddit = ""
    private var text: NotchStreakStrings { FeatureStrings.notchStreaks(l10n.language) }

    private func name(_ provider: NotchStreakProvider) -> String {
        switch provider {
        case .github: return github
        case .leetcode: return leetcode
        case .reddit: return reddit
        }
    }
    private var configured: [NotchStreakProvider] {
        NotchStreakProvider.allCases.filter {
            NotchStreakSupport.isValidUsername(name($0).trimmingCharacters(in: .whitespacesAndNewlines), for: $0)
        }
    }

    var body: some View {
        Group {
            if configured.isEmpty { setup } else { cards }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear { if !preview { service.refreshIfStale() } }
        .notchBand(trailing: {
            if !preview, !configured.isEmpty {
                NotchIconButton(symbol: "arrow.clockwise", title: text.refresh) { service.refreshNow() }
            }
        })
    }

    private var setup: some View {
        VStack(spacing: 8) {
            NotchStreakFlame(size: 28, animates: !preview)
            Text(text.setupTitle).font(.system(size: 13, weight: .semibold))
            Text(text.setupHint).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !preview {
                NotchPillButton(title: text.openSettings, prominent: true) {
                    NotchService.shared.openSettings(showing: .streaks)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cards: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                ForEach(configured) { provider in card(provider, now: context.date) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func card(_ provider: NotchStreakProvider, now: Date) -> some View {
        let snapshot = service.snapshots[provider]
        let failure = service.failures[provider]
        let today = NotchStreakSupport.utcDay(now)
        // A count from before the UTC day turned says nothing about today yet.
        let current = snapshot.flatMap { $0.utcDay == today ? $0 : nil }
        let tint: Color? = current.map { $0.doneToday ? .green : .orange }
        return VStack(spacing: 6) {
            header(provider)
            Spacer(minLength: 0)
            if let snapshot {
                HStack(spacing: 5) {
                    NotchStreakFlame(size: 17, animates: snapshot.streak > 0 && !preview)
                    Text("\(snapshot.streak)")
                        .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Text(snapshot.streak == 1 ? text.dayOne : text.dayMany)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    .padding(.top, -4)
                if let current {
                    status(done: current.doneToday, manual: provider == .reddit)
                } else {
                    Text(text.loading).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            } else if service.loading.contains(provider) {
                ProgressView().controlSize(.small)
            } else if failure == .notFound {
                message(text.notFound, symbol: "person.crop.circle.badge.questionmark")
            } else if failure != nil {
                message(text.unavailable, symbol: "wifi.exclamationmark")
            } else {
                ProgressView().controlSize(.small)
            }
            Spacer(minLength: 0)
            if let snapshot {
                HStack(spacing: 3) {
                    if failure != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    Text("\(text.best) \(snapshot.longest)")
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                .help(updatedText(snapshot, now: now))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder((tint ?? .white).opacity(tint == nil ? 0.08 : 0.35), lineWidth: 1))
    }

    @ViewBuilder private func header(_ provider: NotchStreakProvider) -> some View {
        let label = HStack(spacing: 6) {
            if let image = NotchStreakLogo.image(provider.logoResource) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 16, height: 16).accessibilityHidden(true)
            }
            Text(provider.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        if let url = provider.profileURL(name(provider)), !preview {
            Button { NSWorkspace.shared.open(url) } label: { label.contentShape(Rectangle()) }
                .buttonStyle(.plain).help(text.openProfile).accessibilityLabel("\(provider.name), \(text.openProfile)")
        } else {
            label
        }
    }

    private func message(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private func status(done: Bool, manual: Bool) -> some View {
        let tint: Color = done ? .green : .orange
        let pill = HStack(spacing: 4) {
            Image(systemName: done ? "checkmark.circle.fill" : manual ? "hand.tap.fill" : "circle.dashed")
            Text(done ? text.doneToday : manual ? text.markDone : text.notDoneYet).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(tint.opacity(0.16), in: Capsule())
        if manual, !done, !preview {
            Button { service.markRedditDone() } label: { pill.contentShape(Capsule()) }
                .buttonStyle(.plain).help(text.markDone).accessibilityLabel(text.markDone)
        } else {
            pill
        }
    }

    private func updatedText(_ snapshot: NotchStreakSnapshot, now: Date) -> String {
        let minutes = NotchStreakSupport.ageMinutes(of: snapshot.fetched, now: now)
        return minutes < 1 ? text.updatedNow : String(format: text.updatedFormat, minutes)
    }
}

/// Username fields and the reminder, in the island's Streaks settings.
struct NotchStreakSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchStreakGitHub) private var github = ""
    @AppStorage(DefaultsKey.notchStreakLeetCode) private var leetcode = ""
    @AppStorage(DefaultsKey.notchStreakReddit) private var reddit = ""
    @AppStorage(DefaultsKey.notchStreakReminder) private var reminder = true
    @AppStorage(DefaultsKey.notchStreakReminderMinutes) private var minutes = NotchStreakSupport.defaultReminderMinutes
    @AppStorage(DefaultsKey.notchStreakSound) private var sound = true
    private var text: NotchStreakStrings { FeatureStrings.notchStreaks(l10n.language) }

    private var reminderTime: Binding<Date> {
        Binding {
            let start = Calendar.current.startOfDay(for: Date())
            return Calendar.current.date(byAdding: .minute, value: NotchStreakSupport.clampedMinutes(minutes), to: start) ?? start
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes = NotchStreakSupport.clampedMinutes((parts.hour ?? 20) * 60 + (parts.minute ?? 0))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nameField(text.githubUsername, symbol: "chevron.left.forwardslash.chevron.right", value: $github)
            nameField(text.leetcodeUsername, symbol: "curlybraces", value: $leetcode)
            nameField(text.redditUsername, symbol: "bubble.left.and.bubble.right", value: $reddit)
            Text(text.usernameHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            SettingsRow(symbol: "bell.badge", title: text.reminder, caption: text.reminderHint) {
                Toggle("", isOn: $reminder).labelsHidden().accessibilityLabel(text.reminder).toggleStyle(NyxSwitchToggleStyle())
            }
            if reminder {
                SettingsRow(symbol: "clock", title: text.reminderTime) {
                    DatePicker(text.reminderTime, selection: reminderTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                SettingsRow(symbol: "speaker.wave.2", title: text.sound, caption: text.soundHint) {
                    Toggle("", isOn: $sound).labelsHidden().accessibilityLabel(text.sound).toggleStyle(NyxSwitchToggleStyle())
                }
            }
        }
        .onChange(of: github) { _, _ in NotchStreakService.shared.preferencesChanged() }
        .onChange(of: leetcode) { _, _ in NotchStreakService.shared.preferencesChanged() }
        .onChange(of: reddit) { _, _ in NotchStreakService.shared.preferencesChanged() }
    }

    private func nameField(_ title: String, symbol: String, value: Binding<String>) -> some View {
        SettingsRow(symbol: symbol, title: title) {
            TextField(text.usernamePlaceholder, text: value)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, maxWidth: 200)
                .autocorrectionDisabled()
        }
    }
}
