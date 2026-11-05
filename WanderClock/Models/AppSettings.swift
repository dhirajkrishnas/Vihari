import Foundation
import Observation

nonisolated enum TemperatureUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case celsius = "C"
    case fahrenheit = "F"

    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }

    /// What the person's region prefers (including the Temperature choice in system settings).
    static var regionDefault: TemperatureUnit {
        UnitTemperature(forLocale: .current, usage: .weather).symbol == UnitTemperature.fahrenheit.symbol ? .fahrenheit : .celsius
    }
}

nonisolated enum WindSpeedUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case kilometersPerHour = "kmh"
    case milesPerHour = "mph"
    case metersPerSecond = "ms"

    var id: String { rawValue }
    var symbol: String { unit.symbol }

    var unit: UnitSpeed {
        switch self {
        case .kilometersPerHour: .kilometersPerHour
        case .milesPerHour: .milesPerHour
        case .metersPerSecond: .metersPerSecond
        }
    }

    static var regionDefault: WindSpeedUnit {
        let symbol = UnitSpeed(forLocale: .current, usage: .wind).symbol
        return allCases.first { $0.unit.symbol == symbol } ?? .kilometersPerHour
    }
}

nonisolated enum DistanceUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case kilometers = "km"
    case miles = "mi"

    var id: String { rawValue }
    var symbol: String { unit.symbol }

    var unit: UnitLength { self == .kilometers ? .kilometers : .miles }

    static var regionDefault: DistanceUnit {
        UnitLength(forLocale: .current, usage: .road).symbol == UnitLength.miles.symbol ? .miles : .kilometers
    }
}

nonisolated enum PressureUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case hectopascals = "hpa"
    case inchesOfMercury = "inhg"
    case millibars = "mbar"

    var id: String { rawValue }
    var symbol: String { unit.symbol }

    var unit: UnitPressure {
        switch self {
        case .hectopascals: .hectopascals
        case .inchesOfMercury: .inchesOfMercury
        case .millibars: .millibars
        }
    }

    static var regionDefault: PressureUnit {
        let symbol = UnitPressure(forLocale: .current, usage: .barometric).symbol
        return allCases.first { $0.unit.symbol == symbol } ?? .hectopascals
    }
}

nonisolated enum AppTimeFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case twelveHour = "12h"
    case twentyFourHour = "24h"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .twelveHour: return String(localized: "12-Hour")
        case .twentyFourHour: return String(localized: "24-Hour")
        }
    }

    /// The current locale with this clock forced on it, so times keep the language's own
    /// word order (for example "오전 7:13" in Korean) while showing 12- or 24-hour time.
    var locale: Locale {
        guard self != .system else { return .autoupdatingCurrent }
        var components = Locale.Components(locale: .current)
        components.hourCycle = self == .twelveHour ? .oneToTwelve : .zeroToTwentyThree
        return Locale(components: components)
    }
}

/// User preferences. Stored on the device and mirrored to iCloud key-value storage when sync is on.
/// Units start from the person's region, so most people never need to change them.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var temperatureUnit: TemperatureUnit = .regionDefault { didSet { persist() } }
    var windSpeedUnit: WindSpeedUnit = .regionDefault { didSet { persist() } }
    var distanceUnit: DistanceUnit = .regionDefault { didSet { persist() } }
    var pressureUnit: PressureUnit = .regionDefault { didSet { persist() } }
    var timeFormat: AppTimeFormat = .system { didSet { persist() } }

    /// Whether this device syncs. Each device decides for itself, so this is never synced.
    var isICloudSyncEnabled: Bool = true {
        didSet {
            guard !isApplying, oldValue != isICloudSyncEnabled else { return }
            if isICloudSyncEnabled, NSUbiquitousKeyValueStore.default.data(forKey: Self.settingsKey) != nil {
                // Joining sync: adopt the preferences your other devices already use.
                applyCloudSettings()
            } else {
                persist()
            }
        }
    }

    /// When this device last synced with iCloud.
    private(set) var lastSyncDate: Date?

    private static let settingsKey = "WanderClock_AppSettings_v1"
    private static let lastSyncKey = "WanderClock_LastSyncDate"
    nonisolated private static let timeFormatKey = "WanderClock_TimeFormat"
    @ObservationIgnored private var isApplying = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey) {
            apply(data, fromCloud: false)
        }
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    /// Applies preferences that arrived from iCloud. The sync choice itself stays this device's.
    func applyCloudSettings() {
        guard isICloudSyncEnabled,
              let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.settingsKey) else { return }
        apply(data, fromCloud: true)
        saveLocally()
    }

    /// Records a completed sync on this device only.
    func markSynced(at date: Date = .now) {
        lastSyncDate = date
        UserDefaults.standard.set(date, forKey: Self.lastSyncKey)
    }

    /// Puts units and formats back to their defaults. Used by Delete All Data; the sync choice is kept.
    func resetPreferences() {
        isApplying = true
        temperatureUnit = .regionDefault
        windSpeedUnit = .regionDefault
        distanceUnit = .regionDefault
        pressureUnit = .regionDefault
        timeFormat = .system
        isApplying = false
        lastSyncDate = nil
        UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
        persist()
    }

    private func apply(_ data: Data, fromCloud: Bool) {
        guard let saved = try? JSONDecoder().decode(SavedSettings.self, from: data) else { return }
        isApplying = true
        defer { isApplying = false }
        if let value = saved.temperatureUnit { temperatureUnit = value }
        if let value = saved.windSpeedUnit { windSpeedUnit = value }
        if let value = saved.distanceUnit { distanceUnit = value }
        if let value = saved.pressureUnit { pressureUnit = value }
        if let value = saved.timeFormat { timeFormat = value }
        if !fromCloud, let value = saved.isICloudSyncEnabled { isICloudSyncEnabled = value }
        UserDefaults.standard.set(timeFormat.rawValue, forKey: Self.timeFormatKey)
    }

    private func persist() {
        guard !isApplying else { return }
        saveLocally()
        if isICloudSyncEnabled, let data = encoded(includingSyncChoice: false) {
            NSUbiquitousKeyValueStore.default.set(data, forKey: Self.settingsKey)
        }
    }

    private func saveLocally() {
        if let data = encoded(includingSyncChoice: true) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        UserDefaults.standard.set(timeFormat.rawValue, forKey: Self.timeFormatKey)
    }

    private func encoded(includingSyncChoice: Bool) -> Data? {
        try? JSONEncoder().encode(SavedSettings(
            temperatureUnit: temperatureUnit,
            windSpeedUnit: windSpeedUnit,
            distanceUnit: distanceUnit,
            pressureUnit: pressureUnit,
            timeFormat: timeFormat,
            isICloudSyncEnabled: includingSyncChoice ? isICloudSyncEnabled : nil
        ))
    }

    // MARK: - Formatting

    func formatTemperature(_ celsius: Double) -> String {
        Self.formatTemperature(celsius, unit: temperatureUnit)
    }

    nonisolated static func formatTemperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        let value = unit == .celsius ? celsius : celsius * 9 / 5 + 32
        return "\(Int(value.rounded()).formatted())°"
    }

    func formatWind(kmh: Double) -> String {
        Self.format(Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour).converted(to: windSpeedUnit.unit),
                    fractionDigits: windSpeedUnit == .metersPerSecond ? 1 : 0)
    }

    func formatDistance(km: Double) -> String {
        let distance = Measurement(value: km, unit: UnitLength.kilometers).converted(to: distanceUnit.unit)
        return Self.format(distance, fractionDigits: distance.value < 10 ? 1 : 0)
    }

    func formatPressure(hpa: Double) -> String {
        Self.format(Measurement(value: hpa, unit: UnitPressure.hectopascals).converted(to: pressureUnit.unit),
                    fractionDigits: pressureUnit == .inchesOfMercury ? 2 : 0)
    }

    /// "20%" in the person's language (for example "20 %" in French).
    nonisolated static func formatPercent(_ percent: Int) -> String {
        (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    nonisolated private static func format<U: Dimension>(_ measurement: Measurement<U>, fractionDigits: Int) -> String {
        measurement.formatted(.measurement(
            width: .abbreviated,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0...fractionDigits))
        ))
    }

    /// Formats a time honouring the 12/24-hour choice. Reading `timeFormat` here makes
    /// SwiftUI views refresh when the preference changes.
    func formatTime(date: Date = .now, in timeZone: TimeZone) -> String {
        Self.formatTime(date, in: timeZone, format: timeFormat)
    }

    /// The same time with each part marked (hour, minute, AM/PM), so a view can style
    /// the parts differently.
    func formatTimeParts(date: Date, in timeZone: TimeZone) -> AttributedString {
        date.formatted(Self.timeStyle(in: timeZone, format: timeFormat).attributedStyle)
    }

    /// The locale time pickers should use, so they match the 12/24-hour choice.
    var timeLocale: Locale { timeFormat.locale }

    /// Thread-safe variant for models and App Intents.
    nonisolated static func formatTime(_ date: Date, in timeZone: TimeZone, format: AppTimeFormat? = nil) -> String {
        date.formatted(timeStyle(in: timeZone, format: format))
    }

    nonisolated private static func timeStyle(in timeZone: TimeZone, format: AppTimeFormat?) -> Date.FormatStyle {
        let resolved = format
            ?? UserDefaults.standard.string(forKey: timeFormatKey).flatMap(AppTimeFormat.init(rawValue:))
            ?? .system
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        style.locale = resolved.locale
        return style
    }

    /// Saved preferences. Every field is optional and decoded on its own, so a value this
    /// version doesn't know (or a field it lacks) never throws away the others.
    private struct SavedSettings: Codable {
        var temperatureUnit: TemperatureUnit?
        var windSpeedUnit: WindSpeedUnit?
        var distanceUnit: DistanceUnit?
        var pressureUnit: PressureUnit?
        var timeFormat: AppTimeFormat?
        var isICloudSyncEnabled: Bool?

        init(temperatureUnit: TemperatureUnit?, windSpeedUnit: WindSpeedUnit?, distanceUnit: DistanceUnit?,
             pressureUnit: PressureUnit?, timeFormat: AppTimeFormat?, isICloudSyncEnabled: Bool?) {
            self.temperatureUnit = temperatureUnit
            self.windSpeedUnit = windSpeedUnit
            self.distanceUnit = distanceUnit
            self.pressureUnit = pressureUnit
            self.timeFormat = timeFormat
            self.isICloudSyncEnabled = isICloudSyncEnabled
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            temperatureUnit = try? c.decodeIfPresent(TemperatureUnit.self, forKey: .temperatureUnit)
            windSpeedUnit = try? c.decodeIfPresent(WindSpeedUnit.self, forKey: .windSpeedUnit)
            distanceUnit = try? c.decodeIfPresent(DistanceUnit.self, forKey: .distanceUnit)
            pressureUnit = try? c.decodeIfPresent(PressureUnit.self, forKey: .pressureUnit)
            timeFormat = try? c.decodeIfPresent(AppTimeFormat.self, forKey: .timeFormat)
            isICloudSyncEnabled = try? c.decodeIfPresent(Bool.self, forKey: .isICloudSyncEnabled)
        }
    }
}
