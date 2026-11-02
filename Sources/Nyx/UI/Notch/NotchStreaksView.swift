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
    private var text: NotchStreakStrings { FeatureStrings.notchStreaks(l10n.language) }

    private func name(_ provider: NotchStreakProvider) -> String { provider == .github ? github : leetcode }
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
            HStack(alignment: .top, spacing: 10) {
                ForEach(configured) { provider in card(provider, now: context.date) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func card(_ provider: NotchStreakProvider, now: Date) -> some View {
        let snapshot = service.snapshots[provider]
        let failure = service.failures[provider]
        let today = NotchStreakSupport.utcDay(now)
        // A count from before the UTC day turned says nothing about today yet.
        let current = snapshot.flatMap { $0.utcDay == today ? $0 : nil }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let image = NotchStreakLogo.image(provider.logoResource) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 18, height: 18).accessibilityHidden(true)
                }
                Text(provider.name).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                if let url = provider.profileURL(name(provider)), !preview {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain).help(text.openProfile).accessibilityLabel(text.openProfile)
                }
            }
            if let snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    NotchStreakFlame(size: 20, animates: snapshot.streak > 0 && !preview)
                    Text("\(snapshot.streak)").font(.system(size: 30, weight: .bold)).monospacedDigit()
                    Text(snapshot.streak == 1 ? text.dayOne : text.dayMany)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                }
                if let current {
                    status(done: current.doneToday)
                } else {
                    Text(text.loading).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
                Text("\(text.best) \(snapshot.longest)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            } else if service.loading.contains(provider) {
                ProgressView().controlSize(.small)
                Text(text.loading).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            } else if failure == .notFound {
                Label(text.notFound, systemImage: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            } else if failure != nil {
                Label(text.unavailable, systemImage: "wifi.exclamationmark")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            } else {
                Text(text.loading).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            footer(provider, snapshot: snapshot, failure: failure, now: now)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func status(done: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
            Text(done ? text.doneToday : text.notDoneYet)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(done ? Color.green : Color.orange)
    }

    @ViewBuilder
    private func footer(_ provider: NotchStreakProvider, snapshot: NotchStreakSnapshot?,
                        failure: NotchStreakFailure?, now: Date) -> some View {
        if let snapshot {
            let minutes = NotchStreakSupport.ageMinutes(of: snapshot.fetched, now: now)
            HStack(spacing: 4) {
                if failure != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                Text(minutes < 1 ? text.updatedNow : String(format: text.updatedFormat, minutes))
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
    }
}

/// Username fields and the reminder, in the island's Streaks settings.
struct NotchStreakSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchStreakGitHub) private var github = ""
    @AppStorage(DefaultsKey.notchStreakLeetCode) private var leetcode = ""
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
