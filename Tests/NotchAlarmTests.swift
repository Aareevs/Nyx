import Foundation

/// When an alarm next rings, for one time only and for chosen days.
enum NotchAlarmTests {
    static func run(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            // 2026-11-01 is a Sunday.
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        func fire(_ alarm: NotchAlarm, after: Date) -> Date? {
            NotchAlarmSupport.nextFire(alarm, after: after, calendar: calendar)
        }

        let once = NotchAlarm(hour: 7, minute: 30)
        suite.expect(fire(once, after: date(1, 6, 0)) == date(1, 7, 30), "alarm: a later time rings today")
        suite.expect(fire(once, after: date(1, 7, 30)) == date(2, 7, 30), "alarm: the minute itself has passed")
        suite.expect(fire(once, after: date(1, 20, 0)) == date(2, 7, 30), "alarm: an earlier time rings tomorrow")

        var off = once
        off.enabled = false
        suite.expect(fire(off, after: date(1, 6, 0)) == nil, "alarm: an alarm that is off never rings")

        // Monday and Wednesday: weekdays 2 and 4.
        var days = NotchAlarm(hour: 9, minute: 0)
        days.weekdays = [2, 4]
        suite.expect(fire(days, after: date(1, 12, 0)) == date(2, 9, 0), "alarm: Sunday noon waits for Monday")
        suite.expect(fire(days, after: date(2, 9, 0)) == date(4, 9, 0), "alarm: Monday's ring leads to Wednesday")
        suite.expect(fire(days, after: date(4, 9, 0)) == date(9, 9, 0), "alarm: Wednesday's ring leads to next Monday")

        let early = NotchAlarm(hour: 1, minute: 0)
        let late = NotchAlarm(hour: 23, minute: 0)
        suite.expect(NotchAlarmSupport.ordered([late, early]).map(\.hour) == [1, 23], "alarm: the list reads from the morning")

        let defaults = UserDefaults(suiteName: "com.nyx.tests.alarms")!
        defaults.removePersistentDomain(forName: "com.nyx.tests.alarms")
        NotchAlarmSupport.save([once, days], in: defaults)
        suite.expect(NotchAlarmSupport.load(in: defaults) == [once, days], "alarm: saved alarms read back")
        defaults.set(Data("not json".utf8), forKey: DefaultsKey.notchAlarms)
        suite.expect(NotchAlarmSupport.load(in: defaults).isEmpty, "alarm: damaged data reads as no alarms")
        defaults.removePersistentDomain(forName: "com.nyx.tests.alarms")
    }
}
