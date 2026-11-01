import Foundation

struct NotchAlarmStrings {
    let title: String
    let hour: String
    let minute: String
    let description: String
    let summary: String
    let newAlarm: String
    let editAlarm: String
    let alarmLabel: String
    let defaultLabel: String
    let once: String
    let everyDay: String
    let weekdays: String
    let weekends: String
    let repeatTitle: String
    let save: String
    let cancel: String
    let delete: String
    let back: String
    let stop: String
    let snooze: String
    let ringing: String
    let empty: String
    let emptyHint: String
    let sound: String
    let soundHint: String
    let tomorrow: String
    let today: String
    /// "In 7 h 20 min", under the alarm that is next to ring.
    let inFormat: String
    let hoursShort: String
    let minutesShort: String
    /// Sunday first, as the calendar numbers its weekdays.
    let dayInitials: [String]
}

extension FeatureStrings {
    static func notchAlarms(_ language: AppLanguage) -> NotchAlarmStrings {
        switch language {
        case .enUS: return NotchAlarmStrings(
            title: "Alarms",
            hour: "Hour",
            minute: "Minute",
            description: "Set alarms in the Dynamic Island. They ring with a sound and a notice on the island, repeat on the days you choose, and can be snoozed.",
            summary: "Alarms that ring from the island, once or on chosen days.",
            newAlarm: "New alarm",
            editAlarm: "Edit alarm",
            alarmLabel: "Label",
            defaultLabel: "Alarm",
            once: "Once",
            everyDay: "Every day",
            weekdays: "Weekdays",
            weekends: "Weekends",
            repeatTitle: "Repeat",
            save: "Save",
            cancel: "Cancel",
            delete: "Delete",
            back: "Back to alarms",
            stop: "Stop",
            snooze: "Snooze 5 min",
            ringing: "Ringing",
            empty: "No alarms yet",
            emptyHint: "Press + to set one.",
            sound: "Alarm sound",
            soundHint: "Play a sound until the alarm is stopped, for up to five minutes.",
            tomorrow: "Tomorrow",
            today: "Today",
            inFormat: "In %@",
            hoursShort: "h",
            minutesShort: "min",
            dayInitials: ["S", "M", "T", "W", "T", "F", "S"])
        }
    }
}
