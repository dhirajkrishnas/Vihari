import SwiftUI
import MapKit

struct AddCitySheet: View {
    let pinnedCities: [PinnedCity]
    let onAddCity: (PinnedCity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    /// The last search that finished, and whether MapKit couldn't complete it. "No Results"
    /// waits for a finished search, so it doesn't flash while you're still typing.
    @State private var searchedQuery = ""
    @State private var searchFailed = false
    @State private var resolvingItem: MKMapItem?
    @State private var errorMessage: String?
    @FocusState private var searchFocused: Bool

    private struct Suggestion {
        let name: String, country: String, code: String, lat: Double, lon: Double, tz: String

        /// The country in the person's language ("Allemagne" in French), falling back to English.
        var localizedCountry: String {
            Locale.current.localizedString(forRegionCode: code) ?? country
        }
    }

    private let popularCities: [Suggestion] = [
        .init(name: "Singapore", country: "Singapore", code: "SG", lat: 1.3521, lon: 103.8198, tz: "Asia/Singapore"),
        .init(name: "Seoul", country: "South Korea", code: "KR", lat: 37.5665, lon: 126.9780, tz: "Asia/Seoul"),
        .init(name: "Rome", country: "Italy", code: "IT", lat: 41.9028, lon: 12.4964, tz: "Europe/Rome"),
        .init(name: "Berlin", country: "Germany", code: "DE", lat: 52.5200, lon: 13.4050, tz: "Europe/Berlin"),
        .init(name: "Toronto", country: "Canada", code: "CA", lat: 43.6532, lon: -79.3832, tz: "America/Toronto"),
        .init(name: "Hong Kong", country: "Hong Kong", code: "HK", lat: 22.3193, lon: 114.1694, tz: "Asia/Hong_Kong"),
        .init(name: "Honolulu", country: "United States", code: "US", lat: 21.3069, lon: -157.8583, tz: "Pacific/Honolulu"),
        .init(name: "Buenos Aires", country: "Argentina", code: "AR", lat: -34.6037, lon: -58.3816, tz: "America/Argentina/Buenos_Aires"),
        .init(name: "Mumbai", country: "India", code: "IN", lat: 19.0760, lon: 72.8777, tz: "Asia/Kolkata"),
        .init(name: "Amsterdam", country: "Netherlands", code: "NL", lat: 52.3676, lon: 4.9041, tz: "Europe/Amsterdam"),
        .init(name: "Cape Town", country: "South Africa", code: "ZA", lat: -33.9249, lon: 18.4241, tz: "Africa/Johannesburg"),
        .init(name: "Auckland", country: "New Zealand", code: "NZ", lat: -36.8485, lon: 174.7633, tz: "Pacific/Auckland")
    ]

    var body: some View {
        SheetNavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                #if os(macOS)
                // A search field needs a toolbar on the Mac, so the sheet has its own under the title.
                .macSheetHeader(Text("Pin New City")) {
                    MacSearchField(text: $searchText, prompt: Text("Search Cities"), isFocused: $searchFocused)
                }
                .macSheetFooter {
                    Button(role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                #else
                .navigationTitle("Pin New City")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
                .searchable(text: $searchText, placement: Self.searchPlacement, prompt: Text("Search Cities"))
                .searchFocused($searchFocused)
                #endif
                .background(SheetBackground())
                .autocorrectionDisabled()
                .task(id: searchText) { await search(searchText) }
                .alert("Couldn’t Add City", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
                .onAppear { searchFocused = true }
        }
    }

    #if !os(macOS)
    /// The search field sits under the title on iPhone and iPad, and where the system puts it on Vision Pro.
    private static var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }
    #endif

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var content: some View {
        let query = trimmedQuery
        if query.count < 2 {
            suggestions
        } else if !results.isEmpty {
            // Earlier results stay up while a longer query loads.
            resultsList
        } else if searchedQuery == query, searchFailed {
            ContentUnavailableView {
                Label("Can’t Search Right Now", systemImage: "wifi.slash")
            } description: {
                Text("Check your connection and try again.")
            }
        } else if searchedQuery == query {
            ContentUnavailableView.search(text: query)
        } else {
            ProgressView()
                .padding(.top, 40)
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(results, id: \.self) { item in
                    let coordinate = item.location.coordinate
                    CityRow(
                        name: Self.cityName(for: item),
                        detail: item.addressRepresentations?.cityWithContext ?? item.addressRepresentations?.regionName ?? "",
                        timeZone: item.timeZone,
                        isPinned: isPinned(latitude: coordinate.latitude, longitude: coordinate.longitude),
                        isResolving: resolvingItem == item
                    ) {
                        Task { await add(item) }
                    }
                    .disabled(resolvingItem != nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .dismissesKeyboardOnScroll()
    }

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Suggestions", systemImage: "globe")

                ForEach(popularCities, id: \.name) { suggestion in
                    CityRow(
                        name: suggestion.name,
                        detail: suggestion.localizedCountry,
                        timeZone: TimeZone(identifier: suggestion.tz),
                        isPinned: isPinned(latitude: suggestion.lat, longitude: suggestion.lon)
                    ) {
                        onAddCity(PinnedCity(
                            name: suggestion.name, country: suggestion.localizedCountry, countryCode: suggestion.code,
                            latitude: suggestion.lat, longitude: suggestion.lon,
                            timeZoneIdentifier: suggestion.tz
                        ))
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .dismissesKeyboardOnScroll()
    }

    // MARK: - Search

    private func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            searchedQuery = ""
            searchFailed = false
            return
        }
        // Wait for a pause in typing.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = .address
        request.addressFilter = MKAddressFilter(including: .locality)
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = response.mapItems
            searchFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            // MapKit reports "nothing found" as an error too; that's an ordinary empty result.
            searchFailed = (error as? MKError)?.code != .placemarkNotFound
        }
        searchedQuery = trimmed
    }

    private func add(_ item: MKMapItem) async {
        resolvingItem = item
        defer { resolvingItem = nil }

        // Prefer the time zone MapKit returns; otherwise reverse-geocode the coordinate.
        var timeZone = item.timeZone
        if timeZone == nil, let request = MKReverseGeocodingRequest(location: item.location) {
            timeZone = try? await request.mapItems.first?.timeZone
        }
        guard let timeZone else {
            errorMessage = String(localized: "Vihari couldn’t find the time zone for \(Self.cityName(for: item)). Check your connection and try again.")
            return
        }

        let code = item.addressRepresentations?.region?.identifier ?? ""
        let coordinate = item.location.coordinate
        onAddCity(PinnedCity(
            name: Self.cityName(for: item),
            country: item.addressRepresentations?.regionName ?? "",
            countryCode: code,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: timeZone.identifier
        ))
        dismiss()
    }

    private func isPinned(latitude: Double, longitude: Double) -> Bool {
        pinnedCities.contains { abs($0.latitude - latitude) < 0.05 && abs($0.longitude - longitude) < 0.05 }
    }

    private static func cityName(for item: MKMapItem) -> String {
        item.addressRepresentations?.cityName ?? item.name ?? String(localized: "City")
    }
}

/// One city to pin, as a card: its name and region, how far its clock is from yours, and a
/// plus (or a check once it's pinned). Suggestions and search results share it.
private struct CityRow: View {
    let name: String
    let detail: String
    let timeZone: TimeZone?
    let isPinned: Bool
    var isResolving = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let timeZone {
                    Text(TimeZoneMath.badge(forOffset: TimeZoneMath.offset(of: timeZone, at: .now)))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if isResolving {
                    ProgressView()
                } else {
                    Image(systemName: isPinned ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isPinned ? .secondary : .primary)
                }
            }
            .padding(14)
            .contentCard(cornerRadius: 18)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(isPinned)
        .accessibilityHint(isPinned ? Text("Already pinned") : Text("Pins this city"))
    }
}
