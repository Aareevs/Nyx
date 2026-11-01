import Foundation

struct NotchAlarm: Codable, Equatable, Identifiable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var label = ""
    /// Calendar weekday numbers, 1 for Sunday; empty rings once.
    var weekdays: Set<Int> = []
    var enabled = true
}

enum NotchAlarmSupport {
    static let maximumAlarms = 24
    static let snoozeMinutes = 5
    /// An alarm that came due while the Mac slept still rings for this long.
    static let lateTolerance: TimeInterval = 60

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchAlarms.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchAlarmsEnabled)
            && NotchSupport.modules(in: defaults).contains(.alarms)
    }

    static func isSoundEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchAlarmsSound) as? Bool ?? true
    }

    static func load(in defaults: UserDefaults = .standard) -> [NotchAlarm] {
        guard let data = defaults.data(forKey: DefaultsKey.notchAlarms),
              let alarms = try? JSONDecoder().decode([NotchAlarm].self, from: data) else { return [] }
        return Array(alarms.filter { (0..<24).contains($0.hour) && (0..<60).contains($0.minute) }
            .prefix(maximumAlarms))
    }

    static func save(_ alarms: [NotchAlarm], in defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(alarms), forKey: DefaultsKey.notchAlarms)
    }

    /// The first moment after `date` at which the alarm rings, or nil when it is off.
    static func nextFire(_ alarm: NotchAlarm, after date: Date, calendar: Calendar = .current) -> Date? {
        guard alarm.enabled else { return nil }
        var parts = DateComponents(hour: alarm.hour, minute: alarm.minute, second: 0)
        if alarm.weekdays.isEmpty {
            return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime)
        }
        return alarm.weekdays.filter { (1...7).contains($0) }.compactMap { weekday -> Date? in
            parts.weekday = weekday
            return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime)
        }.min()
    }

    /// Alarms in the order of the day, so the list reads from the morning on.
    static func ordered(_ alarms: [NotchAlarm]) -> [NotchAlarm] {
        alarms.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }
}
