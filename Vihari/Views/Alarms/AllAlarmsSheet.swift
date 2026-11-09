import SwiftUI

/// Every alarm in one place, opened from the globe. The next one to ring leads; below it the
/// alarms are grouped by city, in the order the cities are pinned.
struct AllAlarmsSheet: View {
    let store: CityStore
    /// Opens a city. The sheet closes first.
    let onOpenCity: (PinnedCity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scheduler = AlarmScheduler.shared
    @State private var editor: Editor?

    private enum Editor: Identifiable {
        case new(PinnedCity)
        case edit(CityAlarm, PinnedCity)

        var id: String {
            switch self {
            case .new(let city): "new-\(city.id)"
            case .edit(let alarm, _): alarm.id.uuidString
            }
        }
    }

    /// A pinned city and its alarms.
    private struct CityAlarms: Identifiable {
        let city: PinnedCity
        let alarms: [CityAlarm]
        var id: UUID { city.id }
    }

    /// Only alarms of pinned cities: they're the only ones that ring.
    private var groups: [CityAlarms] {
        store.cities.compactMap { city in
            let alarms = store.alarms(for: city)
            return alarms.isEmpty ? nil : CityAlarms(city: city, alarms: alarms)
        }
    }

    var body: some View {
        SheetNavigationStack {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            #if os(macOS)
            .macSheetHeader(Text("Alarms"))
            .macSheetFooter {
                if showsNewAlarmButton { newAlarmButton.fixedSize() }
            } trailing: {
                MacSheetDoneButton()
            }
            #else
            .navigationTitle("Alarms")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                if showsNewAlarmButton {
                    ToolbarItem(placement: .primaryAction) {
                        newAlarmButton
                    }
                }
            }
            #endif
            .background(SheetBackground())
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .new(let city):
                AddAlarmSheet(city: city, existing: nil, onSave: { store.saveAlarm($0) }, onDelete: nil)
            case .edit(let alarm, let city):
                AddAlarmSheet(city: city, existing: alarm, onSave: { store.saveAlarm($0) }, onDelete: {
                    withAnimation { store.deleteAlarm(alarm) }
                })
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 560, idealHeight: 680)
        #endif
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let groups = groups
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if scheduler.authorization == .denied {
                    PermissionBanner()
                }

                if groups.isEmpty {
                    emptyState
                } else {
                    // With a single alarm, its row says it all.
                    if groups.count > 1 || groups[0].alarms.count > 1,
                       case let (alarm, ring, city)? = nextAlarm(in: groups, now: now) {
                        NextAlarmCard(alarm: alarm, ring: ring, now: now) {
                            editor = .edit(alarm, city)
                        }
                        .padding(.bottom, 4)
                    }

                    ForEach(groups) { group in
                        cityHeader(group.city, now: now)
                            .padding(.top, 10)

                        ForEach(group.alarms) { alarm in
                            AlarmItemRow(
                                alarm: alarm,
                                now: now,
                                onSetEnabled: { store.setAlarm(alarm, enabled: $0) },
                                onEdit: { editor = .edit(alarm, group.city) },
                                onDelete: { withAnimation { store.deleteAlarm(alarm) } }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation { store.deleteAlarm(alarm) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .animation(.smooth, value: store.alarms)
        }
        .swipeActionsContainer()
        .scrollIndicators(.hidden)
    }

    /// The enabled alarm that rings soonest, and when.
    private func nextAlarm(in groups: [CityAlarms], now: Date) -> (CityAlarm, Date, PinnedCity)? {
        groups
            .flatMap { group in
                group.alarms.compactMap { alarm in
                    alarm.nextTriggerDate(from: now).map { (alarm, $0, group.city) }
                }
            }
            .min { $0.1 < $1.1 }
    }

    /// The city's name and time now, with a button that opens it.
    private func cityHeader(_ city: PinnedCity, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(city.name)
                .font(.title3.bold())
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Text(AppSettings.formatTime(now, in: city.timeZone))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Open") { onOpenCity(city) }
                .font(.subheadline.weight(.semibold))
                .adaptiveGlassButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel("Open \(city.name)")
        }
    }

    /// With no alarms yet, the empty state has the button instead.
    private var showsNewAlarmButton: Bool {
        !store.cities.isEmpty && !groups.isEmpty
    }

    /// Picks the city for a new alarm. With one city there's nothing to pick.
    @ViewBuilder
    private var newAlarmButton: some View {
        if store.cities.count == 1, let city = store.cities.first {
            Button("New Alarm", systemImage: "plus") { editor = .new(city) }
        } else {
            Menu {
                Section("New Alarm In") {
                    ForEach(store.cities) { city in
                        Button(city.name) { editor = .new(city) }
                    }
                }
            } label: {
                Label("New Alarm", systemImage: "plus")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Alarms", systemImage: "alarm")
        } description: {
            if store.cities.isEmpty {
                Text("Pin a city, then set alarms that ring at its local time.")
            } else {
                Text("Set an alarm in any city and it shows up here.")
            }
        } actions: {
            if !store.cities.isEmpty {
                newAlarmButton
                    .adaptiveGlassButtonStyle(prominent: true)
            }
        }
        .padding(.top, 60)
    }
}

/// The alarm that rings next, large, with when that is in the city and for the person.
private struct NextAlarmCard: View {
    let alarm: CityAlarm
    let ring: Date
    let now: Date
    let onEdit: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Next Alarm", systemImage: "alarm")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(alarm.formattedCityTime)
                    .font(.system(size: timeSize, weight: .light))
                    .monospacedDigit()
                Text(alarm.cityName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(alarm.label)
                .font(.headline)
            Text("\(dayInCity) · \(alarm.travelerContextSummary(from: now))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .contentCard(cornerRadius: 24)
        .contentShape(.rect(cornerRadius: 24))
        .onTapGesture(perform: onEdit)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Edits the alarm")
    }

    /// "Today", "Tomorrow" or "Thu, 20 Nov", on the city's calendar.
    private var dayInCity: String {
        let zone = alarm.timeZone
        let day = CityDay(ring, in: zone)
        let today = CityDay(now, in: zone)
        if day == today { return String(localized: "Today") }
        if day == today.next(in: zone) { return String(localized: "Tomorrow") }
        return day.formatted(in: zone, now: now)
    }
}
