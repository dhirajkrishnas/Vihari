import SwiftUI

/// Creates or edits an alarm that rings at a time in a city's local time: once or on chosen days,
/// and, if the person wants, on (or from) a particular day on the city's calendar.
struct AddAlarmSheet: View {
    let city: PinnedCity
    let existing: CityAlarm?
    let onSave: (CityAlarm) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.shared

    /// Picked in the city's time zone; only its hour and minute count.
    @State private var time: Date
    @State private var label: String
    /// The days it repeats on. None means it rings once.
    @State private var days: Set<AlarmWeekday>
    @State private var hasDay: Bool
    /// Picked on the city's calendar; only its day counts.
    @State private var day: Date
    @State private var confirmingDelete = false

    private static let suggestions: [LocalizedStringResource] = [
        "Wake Up", "Flight", "Check-Out", "Meeting", "Call Family", "Market Open"
    ]

    init(city: PinnedCity, existing: CityAlarm?, onSave: @escaping (CityAlarm) -> Void, onDelete: (() -> Void)?) {
        self.city = city
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.timeZone
        let time = calendar.date(bySettingHour: existing?.hour ?? 8, minute: existing?.minute ?? 30, second: 0, of: .now) ?? .now
        _time = State(initialValue: time)
        // An alarm that kept its automatic name shows the empty field, with that name as the prompt.
        let label = existing?.label ?? ""
        _label = State(initialValue: label == Self.automaticLabel(for: city) ? "" : label)
        _days = State(initialValue: existing?.repeatSchedule.activeWeekdays ?? RepeatSchedule.weekdays.activeWeekdays)
        _hasDay = State(initialValue: existing?.scheduledDay != nil)
        _day = State(initialValue: existing?.scheduledDay?.date(hour: 12, minute: 0, in: city.timeZone) ?? .now)
    }

    private static func automaticLabel(for city: PinnedCity) -> String {
        String(localized: "\(city.name) Alarm")
    }

    private var draft: CityAlarm {
        alarm(on: hasDay ? CityDay(day, in: city.timeZone) : nil)
    }

    private func alarm(on scheduledDay: CityDay?) -> CityAlarm {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        var alarm = CityAlarm(
            id: existing?.id ?? UUID(),
            cityId: city.id,
            cityName: city.name,
            timeZoneIdentifier: city.timeZoneIdentifier,
            hour: parts.hour ?? 8,
            minute: parts.minute ?? 0,
            label: trimmed.isEmpty ? Self.automaticLabel(for: city) : trimmed,
            isEnabled: true,
            repeatSchedule: RepeatSchedule(weekdays: days),
            scheduledDay: scheduledDay,
            createdAt: existing?.createdAt ?? .now
        )
        alarm.modifiedAt = .now
        return alarm
    }

    /// A one-time alarm on a day and time that has already gone by can't ring, so it can't be saved.
    private var hasPassed: Bool {
        guard days.isEmpty, hasDay, let ring = draft.oneTimeRing(after: .now) else { return false }
        return ring <= .now
    }

    var body: some View {
        SheetNavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    timePicker
                    summary
                    scheduleCard
                    labelCard
                    #if !os(macOS)
                    // The Mac has it at the leading end of the sheet's buttons.
                    if onDelete != nil { deleteButton }
                    #endif
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .animation(.snappy, value: hasDay)
                .animation(.snappy, value: days)
            }
            .scrollIndicators(.hidden)
            .dismissesKeyboardOnScroll()
            #if os(macOS)
            .macSheetHeader(title, subtitle: cityTimeSubtitle)
            .macSheetFooter {
                if onDelete != nil { deleteButton }
            } trailing: {
                Button(role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                saveButton
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            #else
            .navigationTitle(title)
            .cityTimeSubtitle(cityTimeSubtitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                }
            }
            #endif
            .background(SheetBackground())
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 620, idealHeight: 720)
        #endif
    }

    private var title: Text {
        existing == nil ? Text("New Alarm") : Text("Edit Alarm")
    }

    /// "Seoul time · GMT+9".
    private var cityTimeSubtitle: Text {
        Text("\(city.name) time · \(gmtOffset(of: city.timeZone))")
    }

    private var saveButton: some View {
        Button(role: .confirm) {
            onSave(draft)
            dismiss()
        }
        .disabled(hasPassed)
    }

    // MARK: - Time

    private var timePicker: some View {
        DatePicker("Alarm Time", selection: $time, displayedComponents: .hourAndMinute)
            .labelsHidden()
            #if !os(macOS)
            .datePickerStyle(.wheel)
            #endif
            .environment(\.timeZone, city.timeZone)
            // 12- or 24-hour, as chosen in Settings.
            .environment(\.locale, settings.timeLocale)
            .frame(maxWidth: .infinity)
            #if os(macOS)
            .padding(.top, 12)
            #endif
    }

    /// When it rings next, on the city's calendar and in the person's own time.
    @ViewBuilder
    private var summary: some View {
        VStack(spacing: 4) {
            if hasPassed {
                Label("That time has passed in \(city.name)", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Choose a later time or another day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let next = draft.nextTriggerDate() {
                Text(ringsHeadline(next))
                    .font(.headline)
                Text(yourTime(next))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .contentTransition(.numericText())
        .accessibilityElement(children: .combine)
    }

    /// "Rings tomorrow", "Rings Thu, 20 Nov" or, for a repeating alarm, "Next rings today".
    private func ringsHeadline(_ next: Date) -> String {
        let zone = city.timeZone
        let ringDay = CityDay(next, in: zone)
        let today = CityDay(.now, in: zone)
        let tomorrow = today.next(in: zone)
        let repeats = !days.isEmpty
        switch ringDay {
        case today: return repeats ? String(localized: "Next rings today") : String(localized: "Rings today")
        case tomorrow: return repeats ? String(localized: "Next rings tomorrow") : String(localized: "Rings tomorrow")
        default:
            let date = ringDay.formatted(in: zone)
            return repeats ? String(localized: "Next rings \(date)") : String(localized: "Rings \(date)")
        }
    }

    /// "12:30 AM your time · in 13 hr", with the weekday when it's a different day for the person.
    private func yourTime(_ next: Date) -> String {
        let wait = CityAlarm.timeUntil(next, from: .now)
        guard TimeZoneMath.offset(of: city.timeZone, at: next) != 0 else {
            return String(localized: "In \(wait)", comment: "How long until an alarm rings, for example In 5 hr, 20 min")
        }
        let localTime = AppSettings.formatTime(next, in: .current)
        if CityDay(next, in: .current) == CityDay(next, in: city.timeZone) {
            return String(localized: "\(localTime) your time · in \(wait)")
        }
        let weekday = next.formatted(.dateTime.weekday(.abbreviated))
        return String(localized: "\(localTime) \(weekday) your time · in \(wait)", comment: "When an alarm rings on the person's own clock, on a different day than in the city, for example 4:30 PM Wed your time · in 10 days")
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Repeat")
                Spacer(minLength: 12)
                repeatMenu
            }
            WeekdayPicker(selection: $days)

            Divider()

            Toggle(isOn: dayToggle) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(days.isEmpty ? "Date" : "Starts On", systemImage: "calendar")
                    if hasDay {
                        Text(CityDay(day, in: city.timeZone).formatted(in: city.timeZone))
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                            .contentTransition(.numericText())
                    }
                }
                // Fills the row, so the Mac's switch sits at the trailing edge as on iPhone.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A switch on the Mac too, not a checkbox.
            .toggleStyle(.switch)

            if hasDay {
                DatePicker("Day", selection: $day, in: startOfCityToday..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    // Days on the city's calendar.
                    .environment(\.timeZone, city.timeZone)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .contentCard(cornerRadius: 24)
    }

    /// The common schedules, a tap away. Any other set of days is picked with the circles.
    private var repeatMenu: some View {
        Menu {
            ForEach(RepeatPreset.allCases) { preset in
                Toggle(preset.title, isOn: Binding(
                    get: { days == preset.days },
                    set: { _ in days = preset.days }
                ))
            }
        } label: {
            HStack(spacing: 4) {
                Text(days.isEmpty ? String(localized: "Never") : RepeatSchedule(weekdays: days).title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
        }
        // A plain label: the value reads as a value, not as a tinted button.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Repeat")
    }

    /// Turning the day on starts it on the day the alarm would ring anyway.
    private var dayToggle: Binding<Bool> {
        Binding(
            get: { hasDay },
            set: { isOn in
                if isOn, let next = alarm(on: nil).nextTriggerDate(),
                   let noon = CityDay(next, in: city.timeZone).date(hour: 12, minute: 0, in: city.timeZone) {
                    day = noon
                }
                hasDay = isOn
            }
        )
    }

    private var startOfCityToday: Date {
        CityDay(.now, in: city.timeZone).start(in: city.timeZone) ?? .now
    }

    // MARK: - Label

    private var labelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Label", text: $label, prompt: Text(Self.automaticLabel(for: city)))
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                if !label.isEmpty {
                    Button("Clear Label", systemImage: "xmark.circle.fill") { label = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            // Chips scroll right to the card's edge, so it's clear there are more.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.suggestions, id: \.key) { suggestion in
                        let text = String(localized: suggestion)
                        SuggestionChip(title: text, isSelected: label == text) { label = text }
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 16)
        .contentCard(cornerRadius: 24)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Text("Delete Alarm")
                .foregroundStyle(.red)
                #if !os(macOS)
                .frame(maxWidth: .infinity)
                #endif
        }
        #if !os(macOS)
        .adaptiveGlassButtonStyle()
        .controlSize(.large)
        .padding(.top, 4)
        #endif
        .confirmationDialog("Delete this alarm?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Alarm", role: .destructive) {
                onDelete?()
                dismiss()
            }
        }
    }
}

/// The schedules in the Repeat menu.
private enum RepeatPreset: CaseIterable, Identifiable {
    case never, everyDay, weekdays, weekends

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .never: "Never"
        case .everyDay: "Every Day"
        case .weekdays: "Weekdays"
        case .weekends: "Weekends"
        }
    }

    var days: Set<AlarmWeekday> {
        switch self {
        case .never: []
        case .everyDay: RepeatSchedule.everyday.activeWeekdays
        case .weekdays: RepeatSchedule.weekdays.activeWeekdays
        case .weekends: RepeatSchedule.weekends.activeWeekdays
        }
    }
}

/// A suggested label. Like the day circles, it's a quiet fill that turns tangerine when chosen.
private struct SuggestionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row of day circles, starting on the person's first day of the week. Tap a day to add or
/// remove it.
private struct WeekdayPicker: View {
    @Binding var selection: Set<AlarmWeekday>

    @ScaledMetric(relativeTo: .subheadline) private var circle: CGFloat = 38

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AlarmWeekday.localeOrdered, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.singleLetter)
                        .font(.subheadline.weight(.semibold))
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(isOn ? Color.black : Color.primary)
                        .frame(width: min(circle, 46), height: min(circle, 46))
                        .background(Circle().fill(isOn ? Color.accentColor : Color.white.opacity(0.1)))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.fullName)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private extension View {
    /// The city's time zone under the title, where the platform shows a subtitle.
    @ViewBuilder
    func cityTimeSubtitle(_ subtitle: Text) -> some View {
        #if os(visionOS)
        self
        #else
        navigationSubtitle(subtitle)
        #endif
    }
}

/// e.g. "GMT+9" or "GMT+5:30", as it is right now.
private func gmtOffset(of timeZone: TimeZone) -> String {
    var style = Date.FormatStyle.dateTime.timeZone(.localizedGMT(.short))
    style.timeZone = timeZone
    return Date.now.formatted(style)
}
