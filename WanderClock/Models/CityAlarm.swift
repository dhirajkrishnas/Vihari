import Foundation

nonisolated enum AlarmWeekday: Int, CaseIterable, Codable, Hashable, Sendable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    static func < (lhs: AlarmWeekday, rhs: AlarmWeekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Days ordered starting from the user's first weekday (e.g. Monday in most of Europe).
    static var localeOrdered: [AlarmWeekday] {
        let first = Calendar.current.firstWeekday
        return allCases.sorted { (($0.rawValue - first + 7) % 7) < (($1.rawValue - first + 7) % 7) }
    }

    private var symbolIndex: Int { rawValue - 1 }

    var shortName: String { Calendar.current.shortWeekdaySymbols[symbolIndex] }
    var fullName: String { Calendar.current.weekdaySymbols[symbolIndex] }
    var singleLetter: String { Calendar.current.veryShortWeekdaySymbols[symbolIndex] }
}

nonisolated enum RepeatSchedule: Codable, Hashable, Sendable {
    case never
    case everyday
    case weekdays
    case weekends
    case custom(Set<AlarmWeekday>)

    var title: String {
        switch self {
        case .never: return String(localized: "Once")
        case .everyday: return String(localized: "Every Day")
        case .weekdays: return String(localized: "Weekdays")
        case .weekends: return String(localized: "Weekends")
        case .custom(let days):
            switch days {
            case Set(AlarmWeekday.allCases): return String(localized: "Every Day")
            case [.monday, .tuesday, .wednesday, .thursday, .friday]: return String(localized: "Weekdays")
            case [.saturday, .sunday]: return String(localized: "Weekends")
            case []: return String(localized: "Once")
            default:
                return AlarmWeekday.localeOrdered.filter(days.contains).map(\.shortName).formatted(.list(type: .and, width: .narrow))
            }
        }
    }

    var activeWeekdays: Set<AlarmWeekday> {
        switch self {
        case .never: return []
        case .everyday: return Set(AlarmWeekday.allCases)
        case .weekdays: return [.monday, .tuesday, .wednesday, .thursday, .friday]
        case .weekends: return [.saturday, .sunday]
        case .custom(let days): return days
        }
    }

    var repeats: Bool { !activeWeekdays.isEmpty }
}

nonisolated struct CityAlarm: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var cityId: UUID
    var cityName: String
    var timeZoneIdentifier: String
    /// 0–23 in the city's local time.
    var hour: Int
    /// 0–59 in the city's local time.
    var minute: Int
    var label: String
    var isEnabled: Bool
    var repeatSchedule: RepeatSchedule
    /// For one-time alarms: the exact moment it was armed to ring. Once that passes, the alarm turns itself off.
    var oneTimeFireDate: Date?
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        cityId: UUID,
        cityName: String,
        timeZoneIdentifier: String,
        hour: Int,
        minute: Int,
        label: String = String(localized: "Alarm"),
        isEnabled: Bool = true,
        repeatSchedule: RepeatSchedule = .everyday,
        createdAt: Date = .now
    ) {
        self.id = id
        self.cityId = cityId
        self.cityName = cityName
        self.timeZoneIdentifier = timeZoneIdentifier
        self.hour = hour
        self.minute = minute
        self.label = label
        self.isEnabled = isEnabled
        self.repeatSchedule = repeatSchedule
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        if isEnabled && !repeatSchedule.repeats {
            self.oneTimeFireDate = Self.nextOccurrence(hour: hour, minute: minute, in: TimeZone(identifier: timeZoneIdentifier) ?? .current, after: createdAt, weekdays: [])
        }
    }

    // Older saved data has no `modifiedAt` / `oneTimeFireDate` (and an unused `soundName`), so decode leniently.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        cityId = try c.decode(UUID.self, forKey: .cityId)
        cityName = try c.decode(String.self, forKey: .cityName)
        timeZoneIdentifier = try c.decode(String.self, forKey: .timeZoneIdentifier)
        hour = try c.decode(Int.self, forKey: .hour)
        minute = try c.decode(Int.self, forKey: .minute)
        label = try c.decode(String.self, forKey: .label)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        repeatSchedule = try c.decode(RepeatSchedule.self, forKey: .repeatSchedule)
        oneTimeFireDate = try c.decodeIfPresent(Date.self, forKey: .oneTimeFireDate)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// "8:30 AM" style string in the city's local time.
    var formattedCityTime: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return AppSettings.formatTime(date, in: timeZone)
    }

    /// What a ringing alarm says: its label, plus the city unless the label already names it.
    var alertTitle: String {
        label.localizedCaseInsensitiveContains(cityName) ? label : String(localized: "\(label) · \(cityName)", comment: "Ringing alarm title: label and city")
    }

    /// Returns a copy armed (or re-armed) for its next ring. Call whenever the alarm is switched on or edited.
    func armed(from now: Date = .now) -> CityAlarm {
        var copy = self
        copy.isEnabled = true
        copy.modifiedAt = now
        copy.oneTimeFireDate = repeatSchedule.repeats
            ? nil
            : Self.nextOccurrence(hour: hour, minute: minute, in: timeZone, after: now, weekdays: [])
        return copy
    }

    /// True for a one-time alarm whose moment has passed — it should be switched off.
    func hasExpired(at now: Date = .now) -> Bool {
        guard isEnabled, !repeatSchedule.repeats else { return false }
        guard let fireDate = oneTimeFireDate else { return false }
        return fireDate <= now
    }

    /// Next moment this alarm should ring, in absolute time. Handles travel, DST and day boundaries
    /// because the hour/minute are always resolved in the city's own calendar.
    func nextTriggerDate(from now: Date = .now) -> Date? {
        upcomingTriggerDates(from: now, limit: 1).first
    }

    /// The next few ring times, used to pre-schedule repeating alarms so they keep ringing
    /// even if the app isn't opened for a while.
    func upcomingTriggerDates(from now: Date = .now, limit: Int, horizonDays: Int = 21) -> [Date] {
        guard isEnabled, limit > 0 else { return [] }

        guard repeatSchedule.repeats else {
            if let fireDate = oneTimeFireDate {
                return fireDate > now ? [fireDate] : []
            }
            return Self.nextOccurrence(hour: hour, minute: minute, in: timeZone, after: now, weekdays: []).map { [$0] } ?? []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let activeDays = repeatSchedule.activeWeekdays
        let startOfToday = calendar.startOfDay(for: now)
        var results: [Date] = []

        for offset in 0...horizonDays {
            guard results.count < limit,
                  let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let weekday = AlarmWeekday(rawValue: calendar.component(.weekday, from: day)),
                  activeDays.contains(weekday),
                  let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  candidate > now
            else { continue }
            results.append(candidate)
        }
        return results
    }

    /// The next ring time shown in the device's current time zone.
    func formattedLocalDeviceTime(from now: Date = .now) -> String {
        let date = nextTriggerDate(from: now)
            ?? Self.nextOccurrence(hour: hour, minute: minute, in: timeZone, after: now, weekdays: [])
            ?? now
        return AppSettings.formatTime(date, in: .current)
    }

    /// e.g. "11:00 PM your time · in 5 hr, 20 min"
    func travelerContextSummary(from now: Date = .now) -> String {
        guard let next = nextTriggerDate(from: now) else {
            return String(localized: "Off")
        }
        let localTime = AppSettings.formatTime(next, in: .current)
        let remaining = max(60, next.timeIntervalSince(now))
        let units: Set<Duration.UnitsFormatStyle.Unit> = remaining >= 86_400 ? [.days, .hours] : [.hours, .minutes]
        let relative = Duration.seconds(remaining).formatted(
            .units(allowed: units, width: .abbreviated, maximumUnitCount: 2)
        )
        return String(localized: "\(localTime) your time · in \(relative)")
    }

    private static func nextOccurrence(hour: Int, minute: Int, in timeZone: TimeZone, after now: Date, weekdays: Set<AlarmWeekday>) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.nextDate(
            after: now,
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}
