import SwiftUI

/// The time, which the closed island shows on the camera's left while idle.
struct NotchRestingTime: View {
    var size: CGFloat = 13

    /// " AM" or " PM" on a 12-hour clock, nothing on a 24-hour one.
    private static func meridiem(_ date: Date) -> String {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        guard pattern.contains("a") else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return " " + formatter.string(from: date).uppercased()
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            (Text(context.date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(.system(size: size, weight: .medium)).monospacedDigit()
             + Text(Self.meridiem(context.date))
                .font(.system(size: size * 0.6, weight: .semibold)))
                .lineLimit(1).minimumScaleFactor(0.6)
                // The weather is read again as the minute turns, if it is old.
                .task(id: context.date) { NotchWeatherService.shared.refreshIfNeeded() }
        }
    }
}

/// The weather, which it shows on the camera's right.
struct NotchRestingWeather: View {
    @ObservedObject private var weather = NotchWeatherService.shared
    var size: CGFloat = 12

    var body: some View {
        if let reading = weather.reading {
            HStack(spacing: 2) {
                Text(reading.emoji).font(.system(size: size + 1))
                Text("\(reading.temperature)°").font(.system(size: size, weight: .medium)).monospacedDigit()
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
