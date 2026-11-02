import Foundation

/// Streak counting and the two parsers, against the shape of the real answers
/// (a GitHub contributions calendar and a LeetCode GraphQL reply, trimmed).
enum NotchStreakTests {
    // Cells as GitHub's /users/<name>/contributions page writes them, dates out of order.
    private static let githubFixture = """
    <table><tbody><tr>
    <td tabindex="0" data-ix="51" aria-selected="false" aria-describedby="contribution-graph-legend-level-3" style="width: 10px" data-date="2026-10-30" id="contribution-day-component-5-51" data-level="3" role="gridcell" data-view-component="true" class="ContributionCalendar-day"></td>
    <td tabindex="0" data-ix="51" aria-selected="false" aria-describedby="contribution-graph-legend-level-1" style="width: 10px" data-date="2026-10-31" id="contribution-day-component-6-51" data-level="1" role="gridcell" data-view-component="true" class="ContributionCalendar-day"></td>
    <td tabindex="0" data-ix="52" aria-selected="false" aria-describedby="contribution-graph-legend-level-1" style="width: 10px" data-date="2026-11-01" id="contribution-day-component-0-52" data-level="1" role="gridcell" data-view-component="true" class="ContributionCalendar-day"></td>
    <td tabindex="0" data-ix="50" aria-selected="false" style="width: 10px" data-date="2026-10-28" id="contribution-day-component-3-50" data-level="0" role="gridcell" class="ContributionCalendar-day"></td>
    <td tabindex="0" data-ix="50" aria-selected="false" style="width: 10px" data-date="2026-10-29" id="contribution-day-component-4-50" data-level="2" role="gridcell" class="ContributionCalendar-day"></td>
    </tr></tbody></table>
    """

    private static let leetcodeFixture = """
    {"data":{"matchedUser":{"userCalendar":{"streak":3,"totalActiveDays":48,"submissionCalendar":"{\\"1793404800\\": 3, \\"1793491200\\": 2, \\"1793577600\\": 5}"}}}}
    """

    private static let leetcodeMissing = """
    {"errors":[{"message":"That user does not exist.","extensions":{"handled":true}}],"data":{"matchedUser":null}}
    """

    static func run(_ suite: TestSuite) {
        let support = NotchStreakSupport.self
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        func at(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
            utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }

        // Days
        suite.expect(support.utcDay(fromISO: "1970-01-01") == 0, "streak: the epoch is day zero")
        suite.expect(support.utcDay(fromISO: "2026-11-01") == support.utcDay(at(11, 1, 0)), "streak: an ISO date matches its UTC day")
        suite.expect(support.utcDay(fromISO: "2026-11-02")! - support.utcDay(fromISO: "2026-10-31")! == 2, "streak: dates count across a month end")
        suite.expect(support.utcDay(fromISO: "2024-03-01")! - support.utcDay(fromISO: "2024-02-28")! == 2, "streak: a leap day is counted")
        suite.expect(support.utcDay(fromISO: "nope") == nil && support.utcDay(fromISO: "2026-13-01") == nil, "streak: bad dates are refused")
        suite.expect(support.utcDay(at(11, 1, 23)) == support.utcDay(at(11, 1, 0)), "streak: late in the day is still that UTC day")

        // Streaks
        let today = support.utcDay(at(11, 1))
        suite.expect(support.streak(of: [today, today - 1, today - 2], today: today) == 3, "streak: a run ending today counts")
        suite.expect(support.streak(of: [today - 1, today - 2], today: today) == 2, "streak: a run ending yesterday is still alive")
        suite.expect(support.streak(of: [today - 2, today - 3], today: today) == 0, "streak: two idle days end it")
        suite.expect(support.streak(of: [today, today - 2], today: today) == 1, "streak: a gap ends the run")
        suite.expect(support.streak(of: [], today: today) == 0, "streak: no days is no streak")
        suite.expect(support.longestStreak(of: [1, 2, 3, 7, 8]) == 3 && support.longestStreak(of: []) == 0, "streak: the longest run is found")

        // Snapshot
        let done = support.snapshot(days: [today, today - 1], now: at(11, 1))
        suite.expect(done.streak == 2 && done.doneToday && done.longest == 2, "streak: done today with a two day run")
        let open = support.snapshot(days: [today - 1, today - 2, today - 3], now: at(11, 1))
        suite.expect(open.streak == 3 && !open.doneToday, "streak: yesterday's run is alive but today is not done")
        // The service's own count can reach past the calendar's start.
        let edge = support.snapshot(days: [today, today - 1], serverStreak: 40, now: at(11, 1))
        suite.expect(edge.streak == 40, "streak: a run reaching the calendar's edge takes the service's longer count")
        let inner = support.snapshot(days: [today, today - 1, today - 3], serverStreak: 40, now: at(11, 1))
        suite.expect(inner.streak == 2, "streak: a run that ended inside the calendar keeps its own count")

        // GitHub
        let github = support.githubActiveDays(from: githubFixture)
        suite.expect(github == [support.utcDay(fromISO: "2026-10-29")!, support.utcDay(fromISO: "2026-10-30")!,
                                support.utcDay(fromISO: "2026-10-31")!, support.utcDay(fromISO: "2026-11-01")!],
                     "streak: the calendar's cells with a level above zero are the active days")
        let githubSnapshot = support.snapshot(days: github ?? [], now: at(11, 1))
        suite.expect(githubSnapshot.streak == 4 && githubSnapshot.doneToday, "streak: four days to Sunday, done today")
        suite.expect(support.githubActiveDays(from: "<html>Not Found</html>") == nil, "streak: a page without a calendar is not an empty one")

        // LeetCode
        if case .success(let found) = support.leetcodeResult(from: Data(leetcodeFixture.utf8)) {
            suite.expect(found.serverStreak == 3 && found.days.count == 3, "streak: LeetCode's calendar and streak are read")
            suite.expect(found.days.contains(support.utcDay(Date(timeIntervalSince1970: 1_793_404_800))), "streak: its timestamps become UTC days")
        } else {
            suite.expect(false, "streak: LeetCode's fixture parses")
        }
        suite.expect(support.leetcodeResult(from: Data(leetcodeMissing.utf8)) == .failure(.notFound), "streak: an unknown LeetCode user is not found")
        suite.expect(support.leetcodeResult(from: Data("<html>".utf8)) == .failure(.unavailable), "streak: junk is unavailable, not not-found")
        suite.expect(support.leetcodeResult(from: Data("{\"data\":{}}".utf8)) == .failure(.unavailable), "streak: a reply with no user field is unavailable")

        // Reddit, kept by hand
        let redditName = "com.nyx.tests.streaks.reddit"
        let redditDefaults = UserDefaults(suiteName: redditName)!
        redditDefaults.removePersistentDomain(forName: redditName)
        defer { redditDefaults.removePersistentDomain(forName: redditName) }
        suite.expect(support.redditDays(in: redditDefaults).isEmpty, "streak: no Reddit day is marked until a person marks one")
        support.markRedditDay(today - 1, in: redditDefaults)
        support.markRedditDay(today, in: redditDefaults)
        support.markRedditDay(today, in: redditDefaults)
        let marked = support.redditDays(in: redditDefaults)
        suite.expect(marked == [today - 1, today], "streak: a day marked twice is kept once")
        suite.expect(support.snapshot(days: marked, now: at(11, 1)).streak == 2, "streak: marked Reddit days make a streak")
        support.markRedditDay(today + 6000, in: redditDefaults)
        suite.expect(support.redditDays(in: redditDefaults).count == 1, "streak: days far in the past are let go")
        suite.expect(support.isValidUsername("spez", for: .reddit) && !support.isValidUsername("ab", for: .reddit)
                     && !support.isValidUsername("a/b/c", for: .reddit), "streak: Reddit names are 3 to 20 safe characters")

        // Usernames, which end up in a URL
        suite.expect(support.isValidUsername("torvalds", for: .github) && support.isValidUsername("a-b", for: .github), "streak: ordinary GitHub names pass")
        suite.expect(!support.isValidUsername("a/b", for: .github) && !support.isValidUsername("-x", for: .github)
                     && !support.isValidUsername("", for: .github) && !support.isValidUsername("a b", for: .github), "streak: GitHub names with slashes, spaces or a leading dash fail")
        suite.expect(support.isValidUsername("neal_wu", for: .leetcode) && !support.isValidUsername("../x", for: .leetcode), "streak: LeetCode names allow underscores but no path tricks")
        suite.expect(NotchStreakProvider.github.profileURL("torvalds")?.absoluteString == "https://github.com/torvalds"
                     && NotchStreakProvider.github.profileURL("bad name") == nil, "streak: profile links are built only from valid names")

        // Preferences
        let name = "com.nyx.tests.streaks"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        suite.expect(!support.isEnabled(in: defaults), "streak: off until turned on")
        suite.expect(support.configured(in: defaults).isEmpty, "streak: no username, nothing to look up")
        defaults.set(" torvalds ", forKey: DefaultsKey.notchStreakGitHub)
        defaults.set("not valid!", forKey: DefaultsKey.notchStreakLeetCode)
        suite.expect(support.configured(in: defaults) == [.github], "streak: only a valid username is looked up, trimmed")
        suite.expect(support.isReminderEnabled(in: defaults) && support.isSoundEnabled(in: defaults), "streak: reminder and sound default on")
        suite.expect(support.reminderMinutes(in: defaults) == 1200, "streak: the reminder defaults to 20:00")
        defaults.set(99_999, forKey: DefaultsKey.notchStreakReminderMinutes)
        suite.expect(support.reminderMinutes(in: defaults) == 1439, "streak: a reminder time is kept inside the day")

        // Reminder timing, on the UTC clock
        suite.expect(!support.reminderDue(now: at(11, 1, 19), minutes: 1200, dismissedDay: nil, calendar: utc), "streak: not due before the time")
        suite.expect(support.reminderDue(now: at(11, 1, 20), minutes: 1200, dismissedDay: nil, calendar: utc), "streak: due at the time")
        suite.expect(support.reminderDue(now: at(11, 1, 23), minutes: 1200, dismissedDay: "2026-10-31", calendar: utc), "streak: yesterday's Stop does not silence today")
        suite.expect(!support.reminderDue(now: at(11, 1, 23), minutes: 1200, dismissedDay: "2026-11-01", calendar: utc), "streak: Stop silences the rest of the day")
        suite.expect(support.localDayKey(at(11, 1), calendar: utc) == "2026-11-01", "streak: the local day key is yyyy-MM-dd")
        suite.expect(support.atRiskTitle([.github, .leetcode], format: "%@ streak at risk") == "GitHub & LeetCode streak at risk", "streak: the title names every open service")
        suite.expect(support.ageMinutes(of: at(11, 1, 11), now: at(11, 1, 12)) == 60 && support.ageMinutes(of: at(11, 1, 13), now: at(11, 1, 12)) == 0,
                     "streak: age is whole minutes and never negative")

        // Strings
        let strings = FeatureStrings.notchStreaks(.enUS)
        suite.expect(String(format: strings.noticeFormat, 12) == "12 day streak" && String(format: strings.updatedFormat, 5) == "Updated 5 min ago" && String(format: strings.noticeOpenFormat, 1, strings.dayOne) == "1 day · not done yet",
                     "streak: formatted strings fill in their numbers")
    }
}
