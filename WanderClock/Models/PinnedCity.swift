import Foundation
import CoreLocation

nonisolated struct PinnedCity: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var country: String
    var countryCode: String
    var flagEmoji: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var dateAdded: Date

    init(
        id: UUID = UUID(),
        name: String,
        country: String,
        countryCode: String,
        flagEmoji: String = "",
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        dateAdded: Date = .now
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.countryCode = countryCode
        self.flagEmoji = flagEmoji
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dateAdded = dateAdded
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// Seconds this city is ahead of (positive) or behind (negative) the device.
    func offsetFromDevice(at date: Date = .now) -> Int {
        TimeZoneMath.offset(of: timeZone, at: date)
    }

    /// Compact badge text such as "+9 HRS", "-5:30 HRS" or "SAME TIME".
    func relativeTimeDifference(date: Date = .now) -> String {
        TimeZoneMath.badge(forOffset: offsetFromDevice(at: date))
    }

    /// Spoken/accessible description such as "9 hours ahead".
    func relativeTimeDescription(date: Date = .now) -> String {
        TimeZoneMath.sentence(forOffset: offsetFromDevice(at: date))
    }

    /// "Today", "Tomorrow" or "Yesterday" in the city, relative to the device.
    func dayDifferenceStatus(date: Date = .now) -> String {
        TimeZoneMath.dayStatus(of: timeZone, at: date)
    }

    func hourOfDay(date: Date = .now) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }

    /// Rough night check (19:00–06:00 local) used when real sun data isn't available.
    func isNight(date: Date = .now) -> Bool {
        let hour = hourOfDay(date: date)
        return hour < 6 || hour >= 19
    }
}

/// Shared time-zone arithmetic so the app, cards and Siri all agree.
nonisolated enum TimeZoneMath {
    static func offset(of timeZone: TimeZone, at date: Date) -> Int {
        timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
    }

    static func badge(forOffset seconds: Int) -> String {
        guard seconds != 0 else { return String(localized: "SAME TIME", comment: "Badge for a city in your own time zone") }
        let sign = seconds > 0 ? "+" : "−"
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        if minutes == 0 {
            return String(localized: "\(sign)\(hours) HRS", comment: "Hours ahead or behind you, for example +9 HRS")
        }
        let paddedMinutes = minutes.formatted(.number.precision(.integerLength(2)))
        return String(localized: "\(sign)\(hours):\(paddedMinutes) HRS", comment: "Hours and minutes ahead or behind you, for example +5:30 HRS")
    }

    static func sentence(forOffset seconds: Int) -> String {
        guard seconds != 0 else { return String(localized: "same time as you") }
        let duration = Duration.seconds(abs(seconds))
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return seconds > 0
            ? String(localized: "\(duration) ahead")
            : String(localized: "\(duration) behind")
    }

    static func dayStatus(of timeZone: TimeZone, at date: Date) -> String {
        var cityCalendar = Calendar(identifier: .gregorian)
        cityCalendar.timeZone = timeZone
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current

        let cityDay = cityCalendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let localDay = localCalendar.ordinality(of: .day, in: .era, for: date) ?? 0
        switch cityDay - localDay {
        case 0: return String(localized: "Today")
        case 1...: return String(localized: "Tomorrow")
        default: return String(localized: "Yesterday")
        }
    }
}
