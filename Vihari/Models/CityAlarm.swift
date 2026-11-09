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

    /// The schedule that rings on `days`. No days means it rings once; common sets get their own names.
    init(weekdays days: Set<AlarmWeekday>) {
        switch days {
        case []: self = .never
        case Set(AlarmWeekday.allCases): self = .everyday
        case RepeatSchedule.weekdays.activeWeekdays: self = .weekdays
        case RepeatSchedule.weekends.activeWeekdays: self = .weekends
        default: self = .custom(days)
        }
    }
}

/// A day on a city's own calendar, such as 20 November in Seoul. It's kept as a year, month and day
/// rather than a moment, so it stays the same day there wherever the device travels.
nonisolated struct CityDay: Codable, Hashable, Sendable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `timeZone`.
    init(_ date: Date, in timeZone: TimeZone) {
        let parts = Self.calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func < (lhs: CityDay, rhs: CityDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// The first moment of this day in `timeZone`.
    func start(in timeZone: TimeZone) -> Date? {
        let calendar = Self.calendar(in: timeZone)
        return calendar.date(from: DateComponents(year: year, month: month, day: day)).map(calendar.startOfDay)
    }

    /// The moment it's `hour`:`minute` on this day in `timeZone`. If a daylight saving change skips
    /// that time, the first moment after it.
    func date(hour: Int, minute: Int, in timeZone: TimeZone) -> Date? {
        guard let start = start(in: timeZone) else { return nil }
        return Self.calendar(in: timeZone).date(bySettingHour: hour, minute: minute, second: 0, of: start)
    }

    /// The day after this one.
    func next(in timeZone: TimeZone) -> CityDay {
        guard let noon = date(hour: 12, minute: 0, in: timeZone),
              let after = Self.calendar(in: timeZone).date(byAdding: .day, value: 1, to: noon)
        else { return self }
        return CityDay(after, in: timeZone)
    }

    /// e.g. "Fri, 21 Nov", "20 Nov", or with the year when it isn't this year: "Fri, 8 Jan 2027".
    func formatted(withWeekday: Bool = true, in timeZone: TimeZone, now: Date = .now) -> String {
        guard let noon = date(hour: 12, minute: 0, in: timeZone) else { return "" }
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        if withWeekday { style = style.weekday(.abbreviated) }
        if year != CityDay(now, in: timeZone).year { style = style.year() }
        style.timeZone = timeZone
        return noon.formatted(style)
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
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
    /// The day, on the city's calendar, a one-time alarm rings, or the first day a repeating one may
    /// ring. Without one, the alarm rings the next time its hour and minute come round.
    var scheduledDay: CityDay?
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
        scheduledDay: CityDay? = nil,
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
        self.scheduledDay = scheduledDay
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        if isEnabled && !repeatSchedule.repeats {
            self.oneTimeFireDate = oneTimeRing(after: createdAt)
        }
    }

    // Older saved data has no `modifiedAt`, `oneTimeFireDate` or `scheduledDay` (and an unused `soundName`), so decode leniently.
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
        scheduledDay = try c.decodeIfPresent(CityDay.self, forKey: .scheduledDay)
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
        // A ringing alarm shows only a title, so it carries the label and the city's time.
        if label.localizedCaseInsensitiveContains(cityName) {
            return String(localized: "\(label) · \(formattedCityTime)", comment: "Ringing alarm title: label (which names the city) and the city's time")
        }
        return String(localized: "\(label) · \(formattedCityTime) in \(cityName)", comment: "Ringing alarm title: label, the city's time and the city")
    }

    /// Returns a copy armed (or re-armed) for its next ring. Call whenever the alarm is switched on or edited.
    func armed(from now: Date = .now) -> CityAlarm {
        var copy = self
        copy.isEnabled = true
        copy.modifiedAt = now
        if repeatSchedule.repeats {
            copy.oneTimeFireDate = nil
        } else {
            // A one-time alarm whose day has gone by rings at the next chance instead.
            if let ring = oneTimeRing(after: now), ring <= now { copy.scheduledDay = nil }
            copy.oneTimeFireDate = copy.oneTimeRing(after: now)
        }
        return copy
    }

    /// When a one-time alarm rings: on its day if it has one, otherwise the next time its hour and
    /// minute come round after `now`. A day that has gone by gives a moment in the past.
    func oneTimeRing(after now: Date) -> Date? {
        if let scheduledDay { return scheduledDay.date(hour: hour, minute: minute, in: timeZone) }
        return Self.nextOccurrence(hour: hour, minute: minute, in: timeZone, after: now, weekdays: [])
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
            guard let fireDate = oneTimeFireDate ?? oneTimeRing(after: now), fireDate > now else { return [] }
            return [fireDate]
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let activeDays = repeatSchedule.activeWeekdays
        // Counted from the first day it may ring, so one that starts weeks from now is queued already.
        let firstDay = max(now, scheduledDay?.start(in: timeZone) ?? now)
        let startOfFirstDay = calendar.startOfDay(for: firstDay)
        var results: [Date] = []

        for offset in 0...horizonDays {
            guard results.count < limit,
                  let day = calendar.date(byAdding: .day, value: offset, to: startOfFirstDay),
                  let weekday = AlarmWeekday(rawValue: calendar.component(.weekday, from: day)),
                  activeDays.contains(weekday),
                  let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  candidate > now
            else { continue }
            results.append(candidate)
        }
        return results
    }

    /// How it repeats, with its day when it has one: "Weekdays", "Fri, 21 Nov" or "Weekdays from 20 Nov".
    func scheduleSummary(now: Date = .now) -> String {
        guard let scheduledDay else { return repeatSchedule.title }
        guard repeatSchedule.repeats else { return scheduledDay.formatted(in: timeZone, now: now) }
        // Once its first day has come, it's simply a repeating alarm.
        guard scheduledDay > CityDay(now, in: timeZone) else { return repeatSchedule.title }
        let start = scheduledDay.formatted(withWeekday: false, in: timeZone, now: now)
        return String(localized: "\(repeatSchedule.title) from \(start)", comment: "A repeating alarm's days and the day it starts, for example Weekdays from 20 Nov")
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
        return String(localized: "\(localTime) your time · in \(Self.timeUntil(next, from: now))")
    }

    /// How long until `date`, e.g. "5 hr, 20 min" or "10 days, 3 hr".
    static func timeUntil(_ date: Date, from now: Date) -> String {
        let remaining = max(60, date.timeIntervalSince(now))
        let units: Set<Duration.UnitsFormatStyle.Unit> = remaining >= 86_400 ? [.days, .hours] : [.hours, .minutes]
        return Duration.seconds(remaining).formatted(.units(allowed: units, width: .abbreviated, maximumUnitCount: 2))
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
