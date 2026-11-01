import SwiftUI

struct NotchAlarmsView: View {
    let size: CGSize
    @Environment(\.notchSettingsPreview) private var preview
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NotchAlarmService.shared
    @State private var editing: NotchAlarm?
    private var text: NotchAlarmStrings { FeatureStrings.notchAlarms(l10n.language) }

    var body: some View {
        Group {
            if let alarm = editing {
                NotchAlarmEditor(alarm: alarm, isNew: !service.alarms.contains { $0.id == alarm.id }, text: text) {
                    editing = nil
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.locale, l10n.language.formattingLocale())
        .onChange(of: editing != nil) { _, open in
            guard !preview else { return }
            NotchService.shared.setPageLayer(.alarms, close: open ? { editing = nil } : nil)
        }
        .onDisappear { if !preview { NotchService.shared.setPageLayer(.alarms, close: nil) } }
        .notchBand(trailing: {
            if editing == nil, !preview, service.alarms.count < NotchAlarmSupport.maximumAlarms {
                NotchIconButton(symbol: "plus", title: text.newAlarm) { editing = Self.blank() }
            }
        })
    }

    /// A new alarm starts at the next full hour.
    private static func blank() -> NotchAlarm {
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0),
                                             matchingPolicy: .nextTime) ?? Date()
        return NotchAlarm(hour: Calendar.current.component(.hour, from: next), minute: 0)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let ringing = service.ringing { ringingCard(ringing) }
            if service.alarms.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "alarm").font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white.opacity(0.45)).accessibilityHidden(true)
                    Text(text.empty).font(.system(size: 13, weight: .semibold))
                    Text(text.emptyHint).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TimelineView(.everyMinute) { context in
                    let next = service.upcoming(after: context.date)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(service.alarms) { alarm in
                                row(alarm, isNext: next?.alarm.id == alarm.id ? next?.date : nil, now: context.date)
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
    }

    private func ringingCard(_ alarm: NotchAlarm) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "alarm.waves.left.and.right.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(alarm.label.isEmpty ? text.defaultLabel : alarm.label)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(text.ringing).font(.system(size: 11)).foregroundStyle(.orange)
            }
            Spacer(minLength: 6)
            NotchPillButton(title: text.snooze) { service.snooze() }
            NotchPillButton(title: text.stop, prominent: true) { service.dismiss() }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ alarm: NotchAlarm, isNext: Date?, now: Date) -> some View {
        HStack(spacing: 12) {
            Button { editing = alarm } label: {
                HStack(spacing: 12) {
                    Text(Self.time(alarm)).font(.system(size: 26, weight: .light)).monospacedDigit()
                        .foregroundStyle(.white.opacity(alarm.enabled ? 1 : 0.4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alarm.label.isEmpty ? text.defaultLabel : alarm.label)
                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                            .foregroundStyle(.white.opacity(alarm.enabled ? 0.9 : 0.4))
                        Text(subtitle(alarm, isNext: isNext, now: now)).font(.system(size: 11)).lineLimit(1)
                            .foregroundStyle(.white.opacity(alarm.enabled ? 0.6 : 0.35))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Self.time(alarm)), \(alarm.label.isEmpty ? text.defaultLabel : alarm.label)")
            Toggle("", isOn: Binding(get: { alarm.enabled }, set: { service.setEnabled($0, for: alarm) }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    static func time(_ alarm: NotchAlarm) -> String {
        let date = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func subtitle(_ alarm: NotchAlarm, isNext: Date?, now: Date) -> String {
        var parts = [repeatText(alarm.weekdays)]
        if let isNext {
            let minutes = max(1, Int(isNext.timeIntervalSince(now) / 60) + 1)
            let span = minutes >= 60
                ? "\(minutes / 60) \(text.hoursShort)" + (minutes % 60 == 0 ? "" : " \(minutes % 60) \(text.minutesShort)")
                : "\(minutes) \(text.minutesShort)"
            parts.append(String(format: text.inFormat, span))
        }
        return parts.joined(separator: " · ")
    }

    private func repeatText(_ days: Set<Int>) -> String {
        if days.isEmpty { return text.once }
        if days.count == 7 { return text.everyDay }
        if days == [2, 3, 4, 5, 6] { return text.weekdays }
        if days == [1, 7] { return text.weekends }
        return days.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: " ")
    }
}

private struct NotchAlarmEditor: View {
    @State var alarm: NotchAlarm
    let isNew: Bool
    let text: NotchAlarmStrings
    let close: () -> Void
    @FocusState private var labelFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    NotchIconButton(symbol: "chevron.left", title: text.back, action: close)
                    Text(isNew ? text.newAlarm : text.editAlarm).font(.system(size: 13, weight: .semibold))
                }
                // Scroll over a column, click a number beside it, or use the arrow keys.
                HStack(spacing: 4) {
                    TimeDigitWheel(title: text.hour, range: 24, value: $alarm.hour, tint: .white)
                    Text(":").font(.system(size: 24, weight: .medium)).foregroundStyle(.tertiary)
                    TimeDigitWheel(title: text.minute, range: 60, value: $alarm.minute, tint: .white)
                }
                .frame(maxWidth: .infinity)
                TextField(text.alarmLabel, text: $alarm.label)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($labelFocused)
                    .padding(.horizontal, 12).frame(height: 34)
                    .modifier(NotchControlSurface(cornerRadius: 12))
                    .onSubmit(save)
                    .accessibilityLabel(text.alarmLabel)
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.repeatTitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in dayChip(day) }
                    }
                }
                HStack(spacing: 8) {
                    NotchPillButton(title: text.cancel, action: close)
                    if !isNew {
                        NotchPillButton(title: text.delete) {
                            NotchAlarmService.shared.delete(alarm)
                            close()
                        }
                    }
                    NotchPillButton(title: text.save, prominent: true, action: save)
                }
            }
            .padding(.horizontal, 2).padding(.bottom, 4)
        }
        .scrollIndicators(.automatic)
    }

    private func save() {
        alarm.label = alarm.label.trimmingCharacters(in: .whitespacesAndNewlines)
        alarm.enabled = true
        NotchAlarmService.shared.save(alarm)
        close()
    }

    private func dayChip(_ day: Int) -> some View {
        let on = alarm.weekdays.contains(day)
        return Button {
            if on { alarm.weekdays.remove(day) } else { alarm.weekdays.insert(day) }
        } label: {
            Text(text.dayInitials[day - 1]).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? .black : .white.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(on ? Color.white : .white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
