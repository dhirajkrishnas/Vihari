import Foundation
import AppIntents
import SwiftUI

struct GetCityWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "Get City Weather"
    static let description = IntentDescription("Tells you the current weather and temperature in a pinned city.")

    @Parameter(title: "City")
    var city: PinnedCityEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the weather in \(\.$city)")
    }

    init() {}

    init(city: PinnedCityEntity) {
        self.city = city
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let pinned = city.city else { throw CityIntentError.cityNotFound }
        guard let report = try? await WeatherServiceManager.shared.fetchWeather(for: pinned) else {
            throw CityIntentError.weatherUnavailable
        }
        let settings = AppSettings.shared
        let temperature = settings.formatTemperature(report.temperature)

        return .result(
            dialog: "It's \(temperature) and \(report.conditionDescription.lowercased()) in \(pinned.name).",
            view: CityWeatherSnippetView(
                cityName: pinned.name,
                temperature: temperature,
                conditionDesc: report.conditionDescription,
                symbolName: report.symbolName,
                highTemp: settings.formatTemperature(report.highTemperature),
                lowTemp: settings.formatTemperature(report.lowTemperature)
            )
        )
    }
}
