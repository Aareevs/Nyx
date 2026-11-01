import SwiftUI

/// Adds an event to Calendar without leaving the island. The event is saved
/// to the user's own calendar, which keeps it in sync with their other devices.
struct NotchCalendarEventForm: View {
    let day: Date
    let text: NotchCalendarStrings
    let close: () -> Void
    @ObservedObject private var calendar = NotchCalendarService.shared
    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var allDay = false
    @State private var choices: [NotchCalendarChoice] = []
    @State private var chosen: String?
    @State private var loaded = false
    @State private var saving = false
    @State private var failed = false
    @FocusState private var titleFocused: Bool

    init(day: Date, text: NotchCalendarStrings, close: @escaping () -> Void) {
        self.day = day
        self.text = text
        self.close = close
        let first = Self.defaultStart(on: day)
        _start = State(initialValue: first)
        _end = State(initialValue: first.addingTimeInterval(3600))
    }

    /// The next full hour for today, and nine in the morning for any other day.
    private static func defaultStart(on day: Date, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) {
            return calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chosen != nil && !saving
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    NotchIconButton(symbol: "chevron.left", title: text.back, action: close)
                    Text(text.newEvent).font(.system(size: 13, weight: .semibold))
                }
                TextField(text.eventTitle, text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($titleFocused)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .modifier(NotchControlSurface(cornerRadius: 12))
                    .onSubmit { if canSave { save() } }
                    .accessibilityLabel(text.eventTitle)
                Toggle(text.allDay, isOn: $allDay).toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12))
                dateRow(text.starts, selection: $start)
                dateRow(text.ends, selection: $end)
                if loaded && choices.isEmpty {
                    Text(text.noWritableCalendar).font(.caption).foregroundStyle(.orange)
                } else if choices.count > 1 {
                    Picker("", selection: Binding(get: { chosen ?? "" }, set: { chosen = $0 })) {
                        ForEach(choices) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden().controlSize(.small)
                }
                if failed { Text(text.saveFailed).font(.caption).foregroundStyle(.orange) }
                HStack(spacing: 8) {
                    NotchPillButton(title: text.cancel, action: close)
                    NotchPillButton(title: text.saveEvent, prominent: true, action: save)
                        .disabled(!canSave).opacity(canSave ? 1 : 0.45)
                }
            }
            .padding(.horizontal, 2).padding(.bottom, 4)
        }
        .scrollIndicators(.automatic)
        .task {
            let result = await calendar.writableCalendars()
            choices = result.choices
            chosen = result.preferred
            loaded = true
            titleFocused = true
        }
        // A start moved past the end carries the end along, as Calendar does.
        .onChange(of: start) { old, new in
            if allDay { end = max(end, new) } else { end = new.addingTimeInterval(max(end.timeIntervalSince(old), 60)) }
        }
        .onChange(of: allDay) { _, on in
            if on { start = Calendar.current.startOfDay(for: start); end = max(end, start) }
        }
    }

    private func dateRow(_ label: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            part(Calendar.current.component(.day, from: selection.wrappedValue), range: 1...31, width: 42,
                 format: { String($0) }) { set(.day, $0, in: selection) }
            part(Calendar.current.component(.month, from: selection.wrappedValue), range: 1...12, width: 52,
                 format: { Calendar.current.shortMonthSymbols[$0 - 1] }) { set(.month, $0, in: selection) }
            let year = Calendar.current.component(.year, from: Date())
            part(Calendar.current.component(.year, from: selection.wrappedValue), range: (year - 1)...(year + 8), width: 54,
                 format: { String($0) }) { set(.year, $0, in: selection) }
            if !allDay {
                part(Calendar.current.component(.hour, from: selection.wrappedValue), range: 0...23, width: 42,
                     format: { String(format: "%02d", $0) }) { set(.hour, $0, in: selection) }
                Text(":").foregroundStyle(.secondary)
                part(Calendar.current.component(.minute, from: selection.wrappedValue) / 5 * 5, range: 0...55, step: 5,
                     width: 42, format: { String(format: "%02d", $0) }) { set(.minute, $0, in: selection) }
            }
        }
    }

    /// A value picked from a menu, never typed, so no half-entered number can
    /// leave the date in a state the field cannot read back.
    private func part(_ value: Int, range: ClosedRange<Int>, step: Int = 1, width: CGFloat,
                      format: @escaping (Int) -> String, choose: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)), id: \.self) { number in
                Button(format(number)) { choose(number) }
            }
        } label: {
            Text(format(value)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.white)
                .frame(width: width, height: 26)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
    }

    /// Changes one part of the date; a day the month lacks lands on its last.
    private func set(_ component: Calendar.Component, _ value: Int, in date: Binding<Date>) {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date.wrappedValue)
        switch component {
        case .day: parts.day = value
        case .month: parts.month = value
        case .year: parts.year = value
        case .hour: parts.hour = value
        default: parts.minute = value
        }
        let day = parts.day ?? 1
        parts.day = 1
        guard let first = calendar.date(from: parts),
              let days = calendar.range(of: .day, in: .month, for: first)?.count else { return }
        parts.day = min(day, days)
        if let next = calendar.date(from: parts) { date.wrappedValue = next }
    }

    private func save() {
        guard canSave, let chosen else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = allDay ? max(start, end) : max(end, start.addingTimeInterval(60))
        saving = true
        failed = false
        Task {
            let saved = await calendar.addEvent(title: name, start: start, end: last, allDay: allDay, calendar: chosen)
            saving = false
            if saved { close() } else { failed = true }
        }
    }
}
