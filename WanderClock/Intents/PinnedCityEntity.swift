import Foundation
import AppIntents

struct PinnedCityEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pinned City"
    static let defaultQuery = PinnedCityQuery()

    let id: UUID
    let name: String
    let country: String
    let timeZoneIdentifier: String

    init(from city: PinnedCity) {
        id = city.id
        name = city.name
        country = city.country
        timeZoneIdentifier = city.timeZoneIdentifier
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(country)")
    }

    /// The live city from the store (nil if it was unpinned since Siri resolved it).
    @MainActor var city: PinnedCity? {
        CityStore.shared.cities.first { $0.id == id }
    }
}

struct PinnedCityQuery: EnumerableEntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PinnedCityEntity] {
        CityStore.shared.cities.filter { identifiers.contains($0.id) }.map(PinnedCityEntity.init(from:))
    }

    @MainActor
    func allEntities() async throws -> [PinnedCityEntity] {
        CityStore.shared.cities.map(PinnedCityEntity.init(from:))
    }

    @MainActor
    func suggestedEntities() async throws -> [PinnedCityEntity] {
        try await allEntities()
    }

    @MainActor
    func entities(matching string: String) async throws -> [PinnedCityEntity] {
        CityStore.shared.cities
            .filter { $0.name.localizedStandardContains(string) || $0.country.localizedStandardContains(string) }
            .map(PinnedCityEntity.init(from:))
    }
}

enum CityIntentError: Error, CustomLocalizedStringResourceConvertible {
    case cityNotFound
    case weatherUnavailable
    case alarmTimeHasPassed(cityName: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .cityNotFound: "That city isn’t pinned in WanderClock anymore."
        case .weatherUnavailable: "Weather isn’t available right now. Try again in a moment."
        case .alarmTimeHasPassed(let cityName): "That time has already passed in \(cityName). Choose a later time or another day."
        }
    }
}
