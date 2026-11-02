import Foundation

struct NotchStreakStrings {
    let title: String
    let description: String
    let summary: String
    /// "12 days" or "1 day", chosen by the caller.
    let dayOne: String
    let dayMany: String
    let doneToday: String
    let notDoneYet: String
    let notSetUp: String
    let setupTitle: String
    let setupHint: String
    let openSettings: String
    let refresh: String
    let openProfile: String
    let loading: String
    let notFound: String
    let unavailable: String
    /// "Updated 5 min ago".
    let updatedFormat: String
    let updatedNow: String
    let best: String
    /// "12 day streak" in the closed island.
    let noticeFormat: String
    let noticeOpenFormat: String
    /// "GitHub streak at risk".
    let atRiskFormat: String
    let stop: String
    let githubUsername: String
    let leetcodeUsername: String
    let redditUsername: String
    let markDone: String
    let done: String
    let usernamePlaceholder: String
    let usernameHint: String
    let reminder: String
    let reminderHint: String
    let reminderTime: String
    let sound: String
    let soundHint: String
}

extension FeatureStrings {
    static func notchStreaks(_ language: AppLanguage) -> NotchStreakStrings {
        switch language {
        case .enUS: return NotchStreakStrings(
            title: "Streaks",
            description: "Follow your GitHub, LeetCode and Reddit streaks in the Dynamic Island, see at a glance whether today is done, and get a reminder only when a streak is still open. Needs your public usernames, and looks them up online.",
            summary: "Your GitHub, LeetCode and Reddit streaks, with a reminder only while one is open.",
            dayOne: "day",
            dayMany: "days",
            doneToday: "Done today",
            notDoneYet: "Not done yet",
            notSetUp: "Add your username in Settings",
            setupTitle: "Set up your streaks",
            setupHint: "Add your GitHub, LeetCode or Reddit username in the island’s Streaks settings. Only the public username is used.",
            openSettings: "Open settings",
            refresh: "Refresh",
            openProfile: "Open profile",
            loading: "Loading…",
            notFound: "User not found",
            unavailable: "Couldn’t load",
            updatedFormat: "Updated %d min ago",
            updatedNow: "Updated just now",
            best: "Best",
            noticeFormat: "%d day streak",
            noticeOpenFormat: "%d %@ · not done yet",
            atRiskFormat: "%@ streak at risk",
            stop: "Stop",
            githubUsername: "GitHub",
            leetcodeUsername: "LeetCode",
            redditUsername: "Reddit",
            markDone: "Mark done",
            done: "Done",
            usernamePlaceholder: "username",
            usernameHint: "Only the public username is sent, to github.com and leetcode.com, and only while Streaks is on. Days count in UTC. GitHub needs private contributions shown on your profile to count them, and Reddit keeps its streak private, so you mark each Reddit day done yourself and Nyx only counts them.",
            reminder: "Daily reminder",
            reminderHint: "At this time, rings like an alarm if a streak is still open, and stops once it is done. It stays quiet when a lookup fails.",
            reminderTime: "Reminder time",
            sound: "Reminder sound",
            soundHint: "Play a sound with the reminder until it is stopped.")
        }
    }
}
