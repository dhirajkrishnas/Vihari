import Foundation
import os

/// Fetches weather from Open-Meteo (free, no API key; data under CC BY 4.0, so the app credits
/// Open-Meteo wherever it shows it). Runs off the main actor.
///
/// - Reports stay fresh for 15 minutes; requests for the same city at the same time share one download.
/// - The last report for each city is saved in the Caches folder, so weather appears straight
///   away at launch and stays visible offline (the weather page says how old it is).
/// - If Open-Meteo says to slow down (HTTP 429), requests pause for as long as it asks.
actor WeatherServiceManager {
    static let shared = WeatherServiceManager()

    enum WeatherError: Error {
        case rateLimited
        case badResponse(Int)
    }

    private var cache: [UUID: WeatherReport] = [:]
    private var inFlight: [UUID: Task<WeatherReport, Error>] = [:]
    private var pausedUntil: Date?
    private var saveTask: Task<Void, Never>?
    private let freshFor: TimeInterval = 15 * 60
    /// Saved reports older than this aren't shown at all.
    private let keepFor: TimeInterval = 12 * 3600
    private let session: URLSession
    private let cacheFile: URL?
    private let log = Logger(subsystem: "com.dhirajkrishnasimhadri.WanderClock", category: "Weather")

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)

        cacheFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "Weather.json")
        if let cacheFile, let data = try? Data(contentsOf: cacheFile),
           let saved = try? JSONDecoder().decode([UUID: WeatherReport].self, from: data) {
            cache = saved
        }
    }

    /// The last report saved for each city, if it's recent enough to show.
    func savedReports() -> [UUID: WeatherReport] {
        cache.filter { Date.now.timeIntervalSince($0.value.lastUpdated) < keepFor }
    }

    func fetchWeather(for city: PinnedCity, forceRefresh: Bool = false) async throws -> WeatherReport {
        if !forceRefresh, let cached = cache[city.id], Date.now.timeIntervalSince(cached.lastUpdated) < freshFor {
            return cached
        }
        if let running = inFlight[city.id] {
            return try await running.value
        }
        let task = Task { try await download(city) }
        inFlight[city.id] = task
        defer { inFlight[city.id] = nil }
        do {
            let report = try await task.value
            cache[city.id] = report
            scheduleSave()
            return report
        } catch {
            log.error("Open-Meteo failed for \(city.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if let cached = cache[city.id], Date.now.timeIntervalSince(cached.lastUpdated) < keepFor { return cached }
            throw error
        }
    }

    /// Drops saved weather for cities that are no longer pinned.
    func keepReports(for cityIDs: Set<UUID>) {
        let before = cache.count
        cache = cache.filter { cityIDs.contains($0.key) }
        if cache.count != before { scheduleSave() }
    }

    func removeAllReports() {
        cache = [:]
        saveTask?.cancel()
        if let cacheFile { try? FileManager.default.removeItem(at: cacheFile) }
    }

    private func download(_ city: PinnedCity) async throws -> WeatherReport {
        if let pausedUntil, pausedUntil > .now { throw WeatherError.rateLimited }
        let (data, response) = try await session.data(from: Self.url(for: city))
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200:
            break
        case 429:
            let wait = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 60
            pausedUntil = .now.addingTimeInterval(min(max(wait, 30), 3600))
            throw WeatherError.rateLimited
        default:
            throw WeatherError.badResponse(http.statusCode)
        }
        let forecast = try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
        return try Self.makeReport(city: city, forecast: forecast)
    }

    /// Writes the cache a moment after the last change, so a refresh of every city writes once.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let cacheFile else { return }
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: cacheFile, options: [.atomic])
            }
        }
    }

    // MARK: - Request

    private static func url(for city: PinnedCity) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", city.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", city.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day,visibility,uv_index,pressure_msl,dew_point_2m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "10")
        ]
        return components.url!
    }

    // MARK: - Mapping

    private static func makeReport(city: PinnedCity, forecast: OpenMeteoForecast) throws -> WeatherReport {
        let now = Date.now
        let current = forecast.current
        let hourly = forecast.hourly
        let daily = forecast.daily
        let isDay = current.isDay == 1
        let condition = WeatherCode(current.weatherCode)

        // The hour that contains "now", used for values only the hourly series provides.
        let hourIndex = hourly.time.lastIndex { Double($0) <= now.timeIntervalSince1970 } ?? 0
        func hourlyValue(_ series: [Double?]?, at index: Int) -> Double? {
            guard let series, series.indices.contains(index) else { return nil }
            return series[index]
        }

        let hourlyItems: [HourlyForecastItem] = (hourIndex..<min(hourIndex + 24, hourly.time.count)).compactMap { index in
            guard let temperature = hourly.temperature2m[index], let code = hourly.weatherCode[index] else { return nil }
            let hourCondition = WeatherCode(code)
            return HourlyForecastItem(
                date: Date(timeIntervalSince1970: TimeInterval(hourly.time[index])),
                temperature: temperature,
                symbolName: hourCondition.symbolName(isDay: (hourly.isDay[index] ?? 1) == 1),
                conditionDescription: hourCondition.description,
                precipitationChancePercent: hourly.precipitationProbability[index] ?? 0
            )
        }

        let dailyItems: [DailyForecastItem] = daily.time.indices.compactMap { index in
            guard let code = daily.weatherCode[index],
                  let low = daily.temperature2mMin[index],
                  let high = daily.temperature2mMax[index] else { return nil }
            let dayCondition = WeatherCode(code)
            return DailyForecastItem(
                date: Date(timeIntervalSince1970: TimeInterval(daily.time[index])),
                symbolName: dayCondition.symbolName(isDay: true),
                conditionDescription: dayCondition.description,
                lowTemperature: low,
                highTemperature: high,
                precipitationChancePercent: daily.precipitationProbabilityMax[index] ?? 0
            )
        }

        let uv = Int((hourlyValue(hourly.uvIndex, at: hourIndex) ?? 0).rounded())
        let pressure = current.pressureMsl
        let laterPressure = hourlyValue(hourly.pressureMsl, at: hourIndex + 3)
        let sunrise = daily.sunrise.first.flatMap { $0 }.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let sunset = daily.sunset.first.flatMap { $0 }.map { Date(timeIntervalSince1970: TimeInterval($0)) }

        return WeatherReport(
            cityId: city.id,
            temperature: current.temperature2m,
            highTemperature: dailyItems.first?.highTemperature ?? current.temperature2m,
            lowTemperature: dailyItems.first?.lowTemperature ?? current.temperature2m,
            conditionDescription: condition.description,
            category: condition.category(isDay: isDay),
            symbolName: condition.symbolName(isDay: isDay),
            isDaylight: isDay,
            feelsLike: current.apparentTemperature,
            humidityPercent: Int(current.relativeHumidity2m.rounded()),
            windSpeedKmh: current.windSpeed10m,
            windDirection: compassDirection(degrees: current.windDirection10m),
            uvIndex: uv,
            uvDescription: uvDescription(uv),
            sunrise: sunrise,
            sunset: sunset,
            visibilityKm: (hourlyValue(hourly.visibility, at: hourIndex) ?? 10_000) / 1000,
            pressureHpa: pressure,
            pressureTrend: pressureTrend(now: pressure, later: laterPressure),
            dewPoint: hourlyValue(hourly.dewPoint2m, at: hourIndex) ?? current.temperature2m,
            hourlyForecast: hourlyItems,
            dailyForecast: dailyItems,
            lastUpdated: now
        )
    }

    private static func compassDirection(degrees: Double) -> String {
        let points = [
            String(localized: "N"), String(localized: "NE"), String(localized: "E"), String(localized: "SE"),
            String(localized: "S"), String(localized: "SW"), String(localized: "W"), String(localized: "NW")
        ]
        let index = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return points[index]
    }

    private static func uvDescription(_ index: Int) -> String {
        switch index {
        case ..<3: String(localized: "Low")
        case 3..<6: String(localized: "Moderate")
        case 6..<8: String(localized: "High")
        case 8..<11: String(localized: "Very High")
        default: String(localized: "Extreme")
        }
    }

    private static func pressureTrend(now: Double, later: Double?) -> String {
        guard let later else { return String(localized: "Steady") }
        if later - now > 1 { return String(localized: "Rising") }
        if now - later > 1 { return String(localized: "Falling") }
        return String(localized: "Steady")
    }
}

// MARK: - WMO weather codes

/// Open-Meteo reports conditions as WMO weather interpretation codes.
nonisolated struct WeatherCode: Sendable {
    let code: Int
    init(_ code: Int) { self.code = code }

    var description: String {
        switch code {
        case 0: String(localized: "Clear")
        case 1: String(localized: "Mostly Clear")
        case 2: String(localized: "Partly Cloudy")
        case 3: String(localized: "Cloudy")
        case 45, 48: String(localized: "Fog")
        case 51, 53, 55: String(localized: "Drizzle")
        case 56, 57: String(localized: "Freezing Drizzle")
        case 61, 63: String(localized: "Rain")
        case 65: String(localized: "Heavy Rain")
        case 66, 67: String(localized: "Freezing Rain")
        case 71, 73: String(localized: "Snow")
        case 75: String(localized: "Heavy Snow")
        case 77: String(localized: "Snow Grains")
        case 80, 81: String(localized: "Showers")
        case 82: String(localized: "Heavy Showers")
        case 85, 86: String(localized: "Snow Showers")
        case 95: String(localized: "Thunderstorms")
        case 96, 99: String(localized: "Thunderstorms with Hail")
        default: String(localized: "Unknown")
        }
    }

    func symbolName(isDay: Bool) -> String {
        switch code {
        case 0, 1: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 66, 67: "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    func category(isDay: Bool) -> WeatherConditionCategory {
        switch code {
        case 0, 1: isDay ? .clearDay : .clearNight
        case 2: isDay ? .partlyCloudyDay : .partlyCloudyNight
        case 3: .cloudy
        case 45, 48: .fog
        case 51, 53, 55, 56, 57, 61, 63, 80, 81: .rain
        case 65, 66, 67, 82: .heavyRain
        case 71, 73, 75, 77, 85, 86: .snow
        case 95, 96, 99: .thunderstorms
        default: .cloudy
        }
    }
}

// MARK: - Response

nonisolated private struct OpenMeteoForecast: Decodable, Sendable {
    struct Current: Decodable, Sendable {
        let temperature2m: Double
        let relativeHumidity2m: Double
        let apparentTemperature: Double
        let isDay: Int
        let weatherCode: Int
        let pressureMsl: Double
        let windSpeed10m: Double
        let windDirection10m: Double

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case relativeHumidity2m = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case isDay = "is_day"
            case weatherCode = "weather_code"
            case pressureMsl = "pressure_msl"
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
        }
    }

    struct Hourly: Decodable, Sendable {
        let time: [Int]
        let temperature2m: [Double?]
        let weatherCode: [Int?]
        let precipitationProbability: [Int?]
        let isDay: [Int?]
        let visibility: [Double?]?
        let uvIndex: [Double?]?
        let pressureMsl: [Double?]?
        let dewPoint2m: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time, visibility
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitationProbability = "precipitation_probability"
            case isDay = "is_day"
            case uvIndex = "uv_index"
            case pressureMsl = "pressure_msl"
            case dewPoint2m = "dew_point_2m"
        }
    }

    struct Daily: Decodable, Sendable {
        let time: [Int]
        let weatherCode: [Int?]
        let temperature2mMax: [Double?]
        let temperature2mMin: [Double?]
        let sunrise: [Int?]
        let sunset: [Int?]
        let precipitationProbabilityMax: [Int?]

        enum CodingKeys: String, CodingKey {
            case time, sunrise, sunset
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }

    let current: Current
    let hourly: Hourly
    let daily: Daily
}
