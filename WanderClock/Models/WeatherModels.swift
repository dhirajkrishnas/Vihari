import Foundation
import SwiftUI

nonisolated enum WeatherConditionCategory: String, Codable, Hashable, Sendable {
    case clearDay, clearNight, partlyCloudyDay, partlyCloudyNight, cloudy
    case rain, heavyRain, thunderstorms, snow, wind, fog

    var accentColor: Color {
        switch self {
        case .clearDay: return .yellow
        case .clearNight: return .indigo
        case .partlyCloudyDay: return .orange
        case .partlyCloudyNight: return .purple
        case .cloudy: return .gray
        case .rain, .heavyRain: return .teal
        case .thunderstorms: return .yellow
        case .snow: return .cyan
        case .wind: return .mint
        case .fog: return .gray
        }
    }
}

nonisolated struct HourlyForecastItem: Identifiable, Codable, Hashable, Sendable {
    var id: Date { date }
    var date: Date
    var temperature: Double
    var symbolName: String
    var conditionDescription: String
    var precipitationChancePercent: Int
}

nonisolated struct DailyForecastItem: Identifiable, Codable, Hashable, Sendable {
    var id: Date { date }
    var date: Date
    var symbolName: String
    var conditionDescription: String
    var lowTemperature: Double
    var highTemperature: Double
    var precipitationChancePercent: Int
}

/// A city's weather, converted from Open-Meteo. Temperatures are Celsius, speeds km/h,
/// distances km and pressure hPa; `AppSettings` converts for display.
nonisolated struct WeatherReport: Codable, Hashable, Sendable {
    var cityId: UUID
    var temperature: Double
    var highTemperature: Double
    var lowTemperature: Double
    var conditionDescription: String
    var category: WeatherConditionCategory
    var symbolName: String
    var isDaylight: Bool
    var feelsLike: Double
    var humidityPercent: Int
    var windSpeedKmh: Double
    var windDirection: String
    var uvIndex: Int
    var uvDescription: String
    var sunrise: Date?
    var sunset: Date?
    var visibilityKm: Double
    var pressureHpa: Double
    var pressureTrend: String
    var dewPoint: Double
    var hourlyForecast: [HourlyForecastItem]
    var dailyForecast: [DailyForecastItem]
    var lastUpdated: Date

    /// Forecast hours from the current hour on. A saved report can be a few hours old,
    /// so hours that have passed are left out.
    func upcomingHours(from now: Date = .now) -> [HourlyForecastItem] {
        hourlyForecast.filter { $0.date.addingTimeInterval(3600) > now }
    }

    /// Forecast days from the city's today on.
    func upcomingDays(from now: Date = .now) -> [DailyForecastItem] {
        dailyForecast.filter { $0.date.addingTimeInterval(86_400) > now }
    }

    /// Overall low/high across the 10-day forecast, used to scale the range bars.
    var forecastTemperatureRange: ClosedRange<Double> {
        let lows = dailyForecast.map(\.lowTemperature)
        let highs = dailyForecast.map(\.highTemperature)
        guard let low = lows.min(), let high = highs.max(), high > low else {
            return (lowTemperature - 1)...(highTemperature + 1)
        }
        return low...high
    }
}

/// Where a city's weather currently stands.
nonisolated enum WeatherState: Equatable, Sendable {
    case loading
    case loaded(WeatherReport)
    case unavailable

    var report: WeatherReport? {
        if case .loaded(let report) = self { return report }
        return nil
    }
}
