import AppKit
import Combine

/// Looks up the GitHub and LeetCode streaks while Streaks is on and a username
/// is set, and never otherwise. One loop wakes every minute; it refreshes what
/// is older than an hour, celebrates a streak on the closed island and, at the
/// reminder time, rings like an alarm for a streak that is still open.
final class NotchStreakService: ObservableObject {
    static let shared = NotchStreakService()

    @Published private(set) var snapshots: [NotchStreakProvider: NotchStreakSnapshot] = [:]
    @Published private(set) var failures: [NotchStreakProvider: NotchStreakFailure] = [:]
    @Published private(set) var loading: Set<NotchStreakProvider> = []
    /// Whether the reminder's notice is the one on the island.
    @Published private(set) var reminderActive = false

    private var loop: Task<Void, Never>?
    private var drain: Task<Void, Never>?
    private var celebrations: [(NotchStreakProvider, NotchStreakSnapshot)] = []
    private var lastAttempt: [NotchStreakProvider: Date] = [:]
    private let alert = NotchTimerAlert()
    private let defaults: UserDefaults
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshots = Self.loadCache(from: defaults)
    }

    // MARK: Lifecycle

    func syncWithPreferences() {
        guard NotchStreakSupport.isEnabled(in: defaults), !NotchStreakSupport.configured(in: defaults).isEmpty else {
            stop(); return
        }
        guard loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        drain?.cancel(); drain = nil
        celebrations = []
        clearReminder()
        loading = []
    }

    /// A username or the switch changed: look again, or let go of what no
    /// longer has a username.
    func preferencesChanged() {
        let configured = Set(NotchStreakSupport.configured(in: defaults))
        snapshots = snapshots.filter { configured.contains($0.key) }
        failures = failures.filter { configured.contains($0.key) }
        Self.saveCache(snapshots, to: defaults)
        lastAttempt = [:]
        if NotchStreakSupport.isEnabled(in: defaults), !configured.isEmpty {
            let wasRunning = loop != nil
            syncWithPreferences()
            // A loop that was already running waits a minute; do not make the new name wait too.
            if wasRunning { Task { @MainActor [weak self] in await self?.tick() } }
        } else {
            stop()
        }
    }

    // MARK: Lookups

    /// A person pressing refresh, or opening the page.
    func refreshNow() {
        guard NotchStreakSupport.isEnabled(in: defaults) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for provider in NotchStreakSupport.configured(in: self.defaults) { await self.refresh(provider) }
        }
    }

    /// The page opened: look again only when what is held is not recent.
    func refreshIfStale() {
        guard NotchStreakSupport.isEnabled(in: defaults) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for provider in NotchStreakSupport.configured(in: self.defaults) where self.isStale(provider, after: 300) {
                await self.refresh(provider)
            }
        }
    }

    private func isStale(_ provider: NotchStreakProvider, after interval: TimeInterval, now: Date = Date()) -> Bool {
        // A failed lookup waits ten minutes, so a busy site is not asked every minute.
        let wait: TimeInterval = failures[provider] != nil ? 600 : min(interval, 60)
        if let attempt = lastAttempt[provider], now.timeIntervalSince(attempt) < wait { return false }
        guard let snapshot = snapshots[provider] else { return true }
        return now.timeIntervalSince(snapshot.fetched) > interval
            || snapshot.utcDay != NotchStreakSupport.utcDay(now)
    }

    @MainActor private func refresh(_ provider: NotchStreakProvider) async {
        guard !loading.contains(provider),
              NotchStreakSupport.isEnabled(in: defaults),
              NotchStreakSupport.configured(in: defaults).contains(provider) else { return }
        let name = NotchStreakSupport.username(provider, in: defaults)
        loading.insert(provider)
        lastAttempt[provider] = Date()
        let result = await Self.fetch(provider, username: name)
        loading.remove(provider)
        // The name may have changed while the lookup was away.
        guard NotchStreakSupport.username(provider, in: defaults) == name else { return }
        switch result {
        case .success(let snapshot): apply(snapshot, for: provider)
        case .failure(let failure): failures[provider] = failure
        }
    }

    private static func fetch(_ provider: NotchStreakProvider, username: String) async -> Result<NotchStreakSnapshot, NotchStreakFailure> {
        do {
            switch provider {
            case .github:
                var request = URLRequest(url: URL(string: "https://github.com/users/\(username)/contributions")!,
                                         timeoutInterval: 20)
                request.setValue("Nyx/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
                request.setValue("text/html", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let status = (response as? HTTPURLResponse)?.statusCode else { return .failure(.unavailable) }
                if status == 404 { return .failure(.notFound) }
                guard status == 200, let html = String(data: data, encoding: .utf8),
                      let days = NotchStreakSupport.githubActiveDays(from: html) else { return .failure(.unavailable) }
                return .success(NotchStreakSupport.snapshot(days: days, now: Date()))
            case .leetcode:
                var request = URLRequest(url: URL(string: "https://leetcode.com/graphql")!, timeoutInterval: 20)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("https://leetcode.com", forHTTPHeaderField: "Referer")
                request.setValue("Nyx/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
                let body: [String: Any] = [
                    "query": "query($u:String!){matchedUser(username:$u){userCalendar{streak totalActiveDays submissionCalendar}}}",
                    "variables": ["u": username]]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .failure(.unavailable) }
                switch NotchStreakSupport.leetcodeResult(from: data) {
                case .success(let found):
                    return .success(NotchStreakSupport.snapshot(days: found.days, serverStreak: found.serverStreak, now: Date()))
                case .failure(let failure): return .failure(failure)
                }
            }
        } catch {
            return .failure(.unavailable)
        }
    }

    // MARK: Results and the closed island

    @MainActor private func apply(_ fresh: NotchStreakSnapshot, for provider: NotchStreakProvider) {
        let previous = snapshots[provider]
        var snapshot = fresh
        snapshot.celebratedDay = previous?.celebratedDay
        failures[provider] = nil
        let today = NotchStreakSupport.localDayKey()
        let extended = snapshot.doneToday && previous?.doneToday == false && previous?.utcDay == snapshot.utcDay
        if (extended || snapshot.celebratedDay != today), snapshot.streak > 0 {
            snapshot.celebratedDay = today
            celebrations.append((provider, snapshot))
            drainCelebrations()
        }
        snapshots[provider] = snapshot
        Self.saveCache(snapshots, to: defaults)
    }

    /// One at a time, so two services answering together each get their moment.
    @MainActor private func drainCelebrations() {
        guard drain == nil else { return }
        drain = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, !self.celebrations.isEmpty {
                let next = self.celebrations.removeFirst()
                if self.celebrate(next.1, for: next.0) { try? await Task.sleep(for: .seconds(4.6)) }
            }
            self?.drain = nil
        }
    }

    /// A few seconds on the closed island: the service's logo and a flame.
    @MainActor @discardableResult
    private func celebrate(_ snapshot: NotchStreakSnapshot, for provider: NotchStreakProvider) -> Bool {
        guard !reminderActive, NotchAlarmService.shared.ringing == nil else { return false }
        let text = FeatureStrings.notchStreaks(L10n.shared.language)
        let detail = snapshot.doneToday
            ? String(format: text.noticeFormat, snapshot.streak)
            : String(format: text.noticeOpenFormat, snapshot.streak, snapshot.streak == 1 ? text.dayOne : text.dayMany)
        let notice = NotchNotice(event: .timer, title: provider.name, detail: detail, symbol: "flame.fill",
                                 logo: provider.logoResource, forced: true, duration: 4)
        return NotchService.shared.show(notice)
    }

    // MARK: Reminder

    @MainActor private func tick() async {
        let now = Date()
        for provider in NotchStreakSupport.configured(in: defaults) where isStale(provider, after: NotchStreakSupport.refreshInterval, now: now) {
            await refresh(provider)
        }
        await evaluateReminder(now: now)
    }

    @MainActor private func evaluateReminder(now: Date) async {
        guard NotchStreakSupport.isReminderEnabled(in: defaults),
              NotchStreakSupport.reminderDue(now: now, minutes: NotchStreakSupport.reminderMinutes(in: defaults),
                                             dismissedDay: defaults.string(forKey: DefaultsKey.notchStreakReminderDismissed)) else {
            clearReminder(); return
        }
        let providers = NotchStreakSupport.configured(in: defaults)
        // Look again while a streak is open, so finishing it ends the reminder.
        for provider in providers where snapshots[provider]?.doneToday != true
            && isStale(provider, after: NotchStreakSupport.reminderRetryInterval, now: now) {
            await refresh(provider)
        }
        // Only a streak read successfully today can be at risk; a failed lookup stays silent.
        let today = NotchStreakSupport.utcDay(Date())
        let open = providers.filter {
            guard let snapshot = snapshots[$0] else { return false }
            return snapshot.utcDay == today && !snapshot.doneToday
        }
        guard !open.isEmpty else { clearReminder(); return }
        // An alarm that is ringing keeps the island; the reminder comes back after it.
        guard NotchAlarmService.shared.ringing == nil else { return }
        let text = FeatureStrings.notchStreaks(L10n.shared.language)
        let notice = NotchNotice(
            event: .timer, title: NotchStreakSupport.atRiskTitle(open, format: text.atRiskFormat),
            detail: text.stop, symbol: "flame.fill", persistent: true, streakReminder: true)
        if !reminderActive || !NotchService.shared.showsStreakNotice {
            if NotchService.shared.show(notice) {
                if !reminderActive { alert.start(enabled: NotchStreakSupport.isSoundEnabled(in: defaults)) }
                reminderActive = true
            }
        }
    }

    /// Stop: quiet for the rest of the day.
    func dismissReminder() {
        defaults.set(NotchStreakSupport.localDayKey(), forKey: DefaultsKey.notchStreakReminderDismissed)
        clearReminder()
    }

    private func clearReminder() {
        alert.stop()
        let wasActive = reminderActive
        reminderActive = false
        if wasActive { NotchService.shared.dismissStreakNotice() }
    }

    // MARK: Cache

    private static func loadCache(from defaults: UserDefaults) -> [NotchStreakProvider: NotchStreakSnapshot] {
        guard let data = defaults.data(forKey: DefaultsKey.notchStreakCache),
              let stored = try? JSONDecoder().decode([String: NotchStreakSnapshot].self, from: data) else { return [:] }
        var result: [NotchStreakProvider: NotchStreakSnapshot] = [:]
        for (key, value) in stored { if let provider = NotchStreakProvider(rawValue: key) { result[provider] = value } }
        return result
    }

    private static func saveCache(_ snapshots: [NotchStreakProvider: NotchStreakSnapshot], to defaults: UserDefaults) {
        let stored = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: DefaultsKey.notchStreakCache) }
    }
}
