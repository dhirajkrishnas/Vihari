import Foundation
import AppIntents
import SwiftUI

struct GetCityTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get City Time"
    static let description = IntentDescription("Tells you the current local time in a pinned city and how far ahead or behind you it is.")

    @Parameter(title: "City")
    var city: PinnedCityEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the time in \(\.$city)")
    }

    init() {}

    init(city: PinnedCityEntity) {
        self.city = city
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let pinned = city.city else { throw CityIntentError.cityNotFound }
        let now = Date.now
        let time = AppSettings.shared.formatTime(date: now, in: pinned.timeZone)
        let difference = pinned.relativeTimeDescription(date: now)

        return .result(
            dialog: "It's \(time) in \(pinned.name), \(difference).",
            view: CityTimeSnippetView(
                cityName: pinned.name,
                localTimeFormatted: time,
                relativeDiff: pinned.relativeTimeDifference(date: now),
                dayStatus: pinned.dayDifferenceStatus(date: now),
                isNight: pinned.isNight(date: now)
            )
        )
    }
}
