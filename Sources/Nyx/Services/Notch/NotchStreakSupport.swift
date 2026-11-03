import Foundation

/// The two services whose daily streaks the island keeps an eye on. Both
/// publish a person's activity on a public page, so no login is needed.
enum NotchStreakProvider: String, CaseIterable, Identifiable, Codable {
    case github, leetcode, reddit
    var id: String { rawValue }

    var name: String {
        switch self {
        case .github: return "GitHub"
        case .leetcode: return "LeetCode"
        case .reddit: return "Reddit"
        }
    }

    var usernameKey: String {
        switch self {
        case .github: return DefaultsKey.notchStreakGitHub
        case .leetcode: return DefaultsKey.notchStreakLeetCode
        case .reddit: return DefaultsKey.notchStreakReddit
        }
    }

    /// The logo shipped in Resources/Images, used only to label the service.
    var logoResource: String { "streak-\(rawValue)" }

    func profileURL(_ username: String) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NotchStreakSupport.isValidUsername(name, for: self) else { return nil }
        switch self {
        case .github: return URL(string: "https://github.com/\(name)")
        case .leetcode: return URL(string: "https://leetcode.com/u/\(name)/")
        case .reddit: return URL(string: "https://www.reddit.com/user/\(name)")
        }
    }
}

/// What one lookup found.
struct NotchStreakSnapshot: Equatable, Codable {
    var streak: Int
    var longest: Int
    var doneToday: Bool
    var fetched: Date
    /// The UTC day (days since 1970) the lookup counted as today.
    var utcDay: Int
    /// The local calendar day a celebration was last shown for, "yyyy-MM-dd".
    var celebratedDay: String?
}

/// What LeetCode's calendar holds: its active days and the streak it counts itself.
struct NotchStreakCalendar: Equatable {
    var days: Set<Int>
    var serverStreak: Int
}

enum NotchStreakFailure: Error, Equatable {
    case notFound
    case unavailable
}

enum NotchStreakSupport {
    static let refreshInterval: TimeInterval = 3600
    static let reminderRetryInterval: TimeInterval = 120
    static let defaultReminderMinutes = 20 * 60

    // MARK: Preferences

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchStreaksEnabled)
            && AppFeature.notchStreaks.isAvailable(in: defaults)
    }

    static func username(_ provider: NotchStreakProvider, in defaults: UserDefaults = .standard) -> String {
        (defaults.string(forKey: provider.usernameKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The services that have a username, so the only ones ever looked up.
    static func configured(in defaults: UserDefaults = .standard) -> [NotchStreakProvider] {
        NotchStreakProvider.allCases.filter { isValidUsername(username($0, in: defaults), for: $0) }
    }

    static func isReminderEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchStreakReminder) as? Bool ?? true
    }

    static func isSoundEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchStreakSound) as? Bool ?? true
    }

    static func reminderMinutes(in defaults: UserDefaults = .standard) -> Int {
        clampedMinutes(defaults.object(forKey: DefaultsKey.notchStreakReminderMinutes) as? Int ?? defaultReminderMinutes)
    }

    static func clampedMinutes(_ value: Int) -> Int { min(max(value, 0), 24 * 60 - 1) }

    /// Usernames are put in a URL, so only the characters each site allows get through.
    static func isValidUsername(_ name: String, for provider: NotchStreakProvider) -> Bool {
        guard !name.isEmpty, name.count <= 39 else { return false }
        switch provider {
        case .github: return name.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$"#, options: .regularExpression) != nil
        case .leetcode: return name.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
        case .reddit: return name.range(of: #"^[A-Za-z0-9_-]{3,20}$"#, options: .regularExpression) != nil
        }
    }

    // MARK: Days

    private static let secondsPerDay = 86_400.0

    /// The UTC day, counted from 1970, that holds the moment.
    static func utcDay(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / secondsPerDay).rounded(.down)) }

    /// The day number a service counts as today. LeetCode counts in UTC;
    /// GitHub and Reddit turn over at local midnight.
    static func day(for provider: NotchStreakProvider, _ date: Date,
                    timeZone: TimeZone = .current) -> Int {
        if provider == .leetcode { return utcDay(date) }
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        return Int((local / secondsPerDay).rounded(.down))
    }

    /// "yyyy-MM-dd" as a UTC day number, without time zones getting involved.
    static func utcDay(fromISO text: String) -> Int? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        // Days from civil: the proleptic Gregorian calendar to a day count.
        var year = parts[0]; let month = parts[1], day = parts[2]
        year -= month <= 2 ? 1 : 0
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The local calendar day, for things that happen once per day on the clock.
    static func localDayKey(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Parsing

    /// The days a GitHub contributions calendar shows activity on. Its page is
    /// a table of cells carrying a date and a level from 0 (none) to 4.
    static func githubActiveDays(from html: String) -> Set<Int>? {
        guard let regex = try? NSRegularExpression(
            pattern: #"data-date="(\d{4}-\d{2}-\d{2})"[^>]*?data-level="(\d)""#) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        var days = Set<Int>()
        var cells = 0
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match, let date = Range(match.range(at: 1), in: html),
                  let level = Range(match.range(at: 2), in: html), let day = utcDay(fromISO: String(html[date])) else { return }
            cells += 1
            if (Int(html[level]) ?? 0) > 0 { days.insert(day) }
        }
        // A page with no calendar is not a page with no activity.
        return cells > 0 ? days : nil
    }

    /// What LeetCode's GraphQL answer holds: the active days, the streak it
    /// counts itself, or why there is none.
    static func leetcodeResult(from data: Data) -> Result<NotchStreakCalendar, NotchStreakFailure> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.unavailable) }
        guard let payload = root["data"] as? [String: Any] else { return .failure(.unavailable) }
        guard let user = payload["matchedUser"] as? [String: Any] else {
            return .failure(root["errors"] != nil || payload["matchedUser"] is NSNull ? .notFound : .unavailable)
        }
        guard let calendar = user["userCalendar"] as? [String: Any] else { return .failure(.unavailable) }
        let serverStreak = calendar["streak"] as? Int ?? 0
        var days = Set<Int>()
        if let text = calendar["submissionCalendar"] as? String, let raw = text.data(using: .utf8),
           let map = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            for (stamp, count) in map {
                guard let seconds = Double(stamp), (count as? Int ?? 0) > 0 else { continue }
                days.insert(utcDay(Date(timeIntervalSince1970: seconds)))
            }
        }
        return .success(NotchStreakCalendar(days: days, serverStreak: serverStreak))
    }

    /// Reddit's own streak is private to the account, so these are the days
    /// marked done by hand, kept as UTC day numbers.
    static func redditDays(in defaults: UserDefaults = .standard) -> Set<Int> {
        Set((defaults.array(forKey: DefaultsKey.notchStreakRedditDays) as? [Int]) ?? [])
    }

    static func markRedditDay(_ day: Int, in defaults: UserDefaults = .standard) {
        // Several years of days is plenty to count a streak from.
        let kept = redditDays(in: defaults).union([day]).filter { $0 > day - 5000 }
        defaults.set(kept.sorted(), forKey: DefaultsKey.notchStreakRedditDays)
    }

    // MARK: Streaks

    /// The run of consecutive days ending today, or yesterday while today is
    /// still open, so a streak is not lost before the day is over.
    static func streak(of days: Set<Int>, today: Int) -> Int {
        var cursor = days.contains(today) ? today : today - 1
        var count = 0
        while days.contains(cursor) { count += 1; cursor -= 1 }
        return count
    }

    static func longestStreak(of days: Set<Int>) -> Int {
        var best = 0, run = 0, previous: Int?
        for day in days.sorted() {
            run = previous == day - 1 ? run + 1 : 1
            best = max(best, run)
            previous = day
        }
        return best
    }

    static func snapshot(days: Set<Int>, serverStreak: Int = 0, now: Date,
                         today: Int? = nil) -> NotchStreakSnapshot {
        let today = today ?? utcDay(now)
        var count = streak(of: days, today: today)
        // A calendar only reaches back so far; when the run starts at its edge,
        // the service's own count may know of a longer one.
        if count > 0, let first = days.min(), days.contains(today) || days.contains(today - 1),
           (days.contains(today) ? today : today - 1) - count + 1 == first {
            count = max(count, serverStreak)
        }
        return NotchStreakSnapshot(streak: count, longest: max(longestStreak(of: days), count),
                                   doneToday: days.contains(today), fetched: now, utcDay: today)
    }

    // MARK: Reminder

    /// Whether the day's reminder is due: on the clock, enabled and not stopped today.
    static func reminderDue(now: Date, minutes: Int, dismissedDay: String?, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let current = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return current >= clampedMinutes(minutes) && dismissedDay != localDayKey(now, calendar: calendar)
    }

    /// "GitHub", "GitHub & LeetCode": the services still open today.
    static func atRiskTitle(_ providers: [NotchStreakProvider], format: String) -> String {
        String(format: format, providers.map(\.name).joined(separator: " & "))
    }

    /// "Updated 5 min ago", rounded down to the minute.
    static func ageMinutes(of date: Date, now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 60))
    }
}
