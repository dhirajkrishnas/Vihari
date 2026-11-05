import SwiftUI

/// Creates or edits an alarm in a city's local time.
struct AddAlarmSheet: View {
    let city: PinnedCity
    let existing: CityAlarm?
    let onSave: (CityAlarm) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.shared

    /// Picked in the city's time zone (the picker below runs in that zone).
    @State private var time: Date
    @State private var label: String
    @State private var repeatOption: RepeatOption
    @State private var customDays: Set<AlarmWeekday>
    @State private var confirmingDelete = false

    private let quickLabels = [
        String(localized: "Daily Standup"), String(localized: "Market Open"), String(localized: "Call Family"),
        String(localized: "Flight"), String(localized: "Market Close")
    ]

    enum RepeatOption: Int, CaseIterable, Identifiable {
        case never, everyday, weekdays, weekends, custom
        var id: Int { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .never: "Once"
            case .everyday: "Daily"
            case .weekdays: "Mon–Fri"
            case .weekends: "Sat–Sun"
            case .custom: "Custom"
            }
        }
    }

    init(city: PinnedCity, existing: CityAlarm?, onSave: @escaping (CityAlarm) -> Void, onDelete: (() -> Void)?) {
        self.city = city
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.timeZone
        let hour = existing?.hour ?? 8
        let minute = existing?.minute ?? 30
        _time = State(initialValue: calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now)
        _label = State(initialValue: existing?.label ?? "")

        switch existing?.repeatSchedule ?? .weekdays {
        case .never: _repeatOption = State(initialValue: .never); _customDays = State(initialValue: [.monday, .tuesday, .wednesday, .thursday, .friday])
        case .everyday: _repeatOption = State(initialValue: .everyday); _customDays = State(initialValue: Set(AlarmWeekday.allCases))
        case .weekdays: _repeatOption = State(initialValue: .weekdays); _customDays = State(initialValue: [.monday, .tuesday, .wednesday, .thursday, .friday])
        case .weekends: _repeatOption = State(initialValue: .weekends); _customDays = State(initialValue: [.saturday, .sunday])
        case .custom(let days): _repeatOption = State(initialValue: .custom); _customDays = State(initialValue: days)
        }
    }

    private var cityCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.timeZone
        return calendar
    }

    private var schedule: RepeatSchedule {
        switch repeatOption {
        case .never: .never
        case .everyday: .everyday
        case .weekdays: .weekdays
        case .weekends: .weekends
        case .custom: .custom(customDays)
        }
    }

    private var draft: CityAlarm {
        let parts = cityCalendar.dateComponents([.hour, .minute], from: time)
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        var alarm = CityAlarm(
            id: existing?.id ?? UUID(),
            cityId: city.id,
            cityName: city.name,
            timeZoneIdentifier: city.timeZoneIdentifier,
            hour: parts.hour ?? 8,
            minute: parts.minute ?? 0,
            label: trimmed.isEmpty ? String(localized: "\(city.name) Alarm") : trimmed,
            isEnabled: true,
            repeatSchedule: schedule,
            createdAt: existing?.createdAt ?? .now
        )
        alarm.modifiedAt = .now
        return alarm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    cityBanner
                    timeSection
                    labelSection
                    repeatSection
                    if let onDelete {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Text("Delete Alarm").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .confirmationDialog("Delete this alarm?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete Alarm", role: .destructive) {
                                onDelete()
                                dismiss()
                            }
                        }
                    }
                }
                .padding(20)
            }
            .dismissesKeyboardOnScroll()
            .background(SheetBackground())
            .navigationTitle(existing == nil ? "New Alarm" : "Edit Alarm")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(repeatOption == .custom && customDays.isEmpty)
                }
            }
        }
    }

    private var cityBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rings on \(city.name) time")
                    .font(.headline)
                Text(city.timeZone.localizedName(for: .generic, locale: .current) ?? city.timeZoneIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .contentCard(cornerRadius: 20)
    }

    private var timeSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "\(city.name) Time", systemImage: "clock")
                .frame(maxWidth: .infinity, alignment: .leading)

            DatePicker("Alarm time", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                #if os(iOS)
                .datePickerStyle(.wheel)
                #endif
                .environment(\.timeZone, city.timeZone)
                // 12- or 24-hour, as chosen in Settings.
                .environment(\.locale, settings.timeLocale)
                .frame(maxWidth: .infinity)

            // What that moment is on the device right now
            Label {
                Text(travelerPreview)
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "airplane.departure").foregroundStyle(.cyan)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(18)
        .contentCard(cornerRadius: 24)
    }

    private var travelerPreview: String {
        guard let next = draft.nextTriggerDate() else { return String(localized: "Choose at least one day") }
        let local = AppSettings.formatTime(next, in: .current)
        let day = Calendar.current.isDateInToday(next) ? String(localized: "today")
            : Calendar.current.isDateInTomorrow(next) ? String(localized: "tomorrow")
            : next.formatted(.dateTime.weekday(.wide))
        return String(localized: "Next rings \(day) at \(local) your time")
    }

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Label", systemImage: "tag")

            TextField("Alarm name", text: $label, prompt: Text("e.g. Morning Standup"))
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(quickLabels, id: \.self) { chip in
                        Button(chip) { label = chip }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .tint(label == chip ? .cyan : .secondary)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .contentCard(cornerRadius: 24)
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Repeat", systemImage: "repeat")

            Picker("Repeat", selection: $repeatOption) {
                ForEach(RepeatOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if repeatOption == .custom {
                HStack(spacing: 8) {
                    ForEach(AlarmWeekday.localeOrdered, id: \.self) { day in
                        let isIncluded = customDays.contains(day)
                        Button {
                            if isIncluded { customDays.remove(day) } else { customDays.insert(day) }
                        } label: {
                            Text(day.singleLetter)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(isIncluded ? .black : .primary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Circle().fill(isIncluded ? Color.cyan : .white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.fullName)
                        .accessibilityAddTraits(isIncluded ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: customDays)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Label {
                Text("Stays on \(city.name) time across time zones, day boundaries and daylight saving changes.")
            } icon: {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .contentCard(cornerRadius: 24)
        .animation(.snappy, value: repeatOption)
    }
}

/// The deep-space gradient used behind sheets.
struct SheetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.16), .black], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
