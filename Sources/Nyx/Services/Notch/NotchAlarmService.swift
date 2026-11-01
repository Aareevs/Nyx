import AppKit
import Combine

/// Alarms live in preferences, so they survive a relaunch, and one task waits
/// for the next to ring. A wake from sleep or a change of the clock reads the
/// schedule again instead of trusting the sleep that was already running.
final class NotchAlarmService: ObservableObject {
    static let shared = NotchAlarmService()
    @Published private(set) var alarms: [NotchAlarm] = NotchAlarmSupport.load()
    @Published private(set) var ringing: NotchAlarm?
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastRang: [UUID: Date] = [:]
    /// A snoozed alarm rings once more at this moment, whatever its schedule.
    private var snoozed: (alarm: NotchAlarm, until: Date)?
    private var running = false
    /// Puts the notice back whenever something took the island from it.
    private var reminder: Task<Void, Never>?
    private let alert = NotchTimerAlert()
    private init() {}

    func syncWithPreferences() {
        guard NotchAlarmSupport.isEnabled() else { stop(); return }
        alarms = NotchAlarmSupport.load()
        if !running {
            running = true
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                [weak self] _ in self?.schedule()
            })
            for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in self?.schedule()
                })
            }
        }
        schedule()
    }

    func stop() {
        task?.cancel(); task = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        running = false
        snoozed = nil
        dismiss()
    }

    // MARK: Editing

    func save(_ alarm: NotchAlarm) {
        var next = alarms
        if let index = next.firstIndex(where: { $0.id == alarm.id }) { next[index] = alarm }
        else if next.count < NotchAlarmSupport.maximumAlarms { next.append(alarm) }
        lastRang[alarm.id] = nil
        commit(next)
    }

    func delete(_ alarm: NotchAlarm) {
        if ringing?.id == alarm.id { dismiss() }
        commit(alarms.filter { $0.id != alarm.id })
    }

    func setEnabled(_ enabled: Bool, for alarm: NotchAlarm) {
        guard var changed = alarms.first(where: { $0.id == alarm.id }) else { return }
        changed.enabled = enabled
        lastRang[alarm.id] = nil
        save(changed)
    }

    private func commit(_ next: [NotchAlarm]) {
        alarms = NotchAlarmSupport.ordered(next)
        NotchAlarmSupport.save(alarms)
        schedule()
    }

    // MARK: Ringing

    func dismiss() {
        alert.stop()
        ringing = nil
        reminder?.cancel(); reminder = nil
        NotchService.shared.dismissAlarmNotice()
    }

    func snooze() {
        guard let alarm = ringing else { return }
        dismiss()
        snoozed = (alarm, Date().addingTimeInterval(TimeInterval(NotchAlarmSupport.snoozeMinutes * 60)))
        schedule()
    }

    /// The next moment anything rings, and what rings then.
    func upcoming(after date: Date = Date()) -> (alarm: NotchAlarm, date: Date)? {
        var best: (alarm: NotchAlarm, date: Date)?
        for alarm in alarms {
            let reference = max(lastRang[alarm.id] ?? .distantPast, date.addingTimeInterval(-NotchAlarmSupport.lateTolerance))
            guard let fire = NotchAlarmSupport.nextFire(alarm, after: reference) else { continue }
            if best == nil || fire < best!.date { best = (alarm, fire) }
        }
        if let snoozed, snoozed.until < (best?.date ?? .distantFuture) { best = (snoozed.alarm, snoozed.until) }
        return best
    }

    private func schedule() {
        task?.cancel(); task = nil
        guard running, NotchAlarmSupport.isEnabled(), let next = upcoming() else { return }
        task = Task { @MainActor [weak self] in
            let wait = max(0, next.date.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(wait), clock: .continuous) }
            catch { return }
            guard let self, !Task.isCancelled, self.running, NotchAlarmSupport.isEnabled() else { return }
            self.task = nil
            self.ring(next.alarm, at: next.date)
        }
    }

    private func ring(_ alarm: NotchAlarm, at date: Date) {
        if snoozed?.alarm.id == alarm.id, let until = snoozed?.until, until <= date.addingTimeInterval(1) { snoozed = nil }
        else { lastRang[alarm.id] = date }
        var stored = alarm
        // An alarm for one time only goes off after it rings.
        if alarm.weekdays.isEmpty, let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            stored.enabled = false
            var next = alarms
            next[index] = stored
            alarms = next
            NotchAlarmSupport.save(next)
        }
        alert.stop()
        ringing = alarm
        let text = FeatureStrings.notchAlarms(L10n.shared.language)
        let notice = NotchNotice(
            event: .timer, title: alarm.label.isEmpty ? text.defaultLabel : alarm.label,
            detail: text.stop, symbol: "alarm", mascot: .surprised, persistent: true)
        _ = NotchService.shared.show(notice)
        NotchService.shared.reactMascot(.surprised)
        reminder?.cancel()
        reminder = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.ringing != nil else { return }
                if !NotchService.shared.showsAlarmNotice { _ = NotchService.shared.show(notice) }
            }
        }
        alert.start(enabled: NotchAlarmSupport.isSoundEnabled())
        schedule()
    }
}
