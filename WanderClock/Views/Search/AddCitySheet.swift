import SwiftUI
import MapKit

struct AddCitySheet: View {
    let pinnedCities: [PinnedCity]
    let onAddCity: (PinnedCity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
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
        NavigationStack {
            VStack(spacing: 16) {
                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                if isSearching && results.isEmpty {
                    ProgressView().padding(.top, 20)
                    Spacer()
                } else if !results.isEmpty {
                    resultsList
                } else if searchText.trimmingCharacters(in: .whitespaces).count >= 2 && !isSearching {
                    ContentUnavailableView.search(text: searchText)
                    Spacer()
                } else {
                    suggestions
                }
            }
            .background(SheetBackground())
            .navigationTitle("Pin New City")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task(id: searchText) { await search(searchText) }
            .alert("Couldn't Add City", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { searchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search cities", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resultsList: some View {
        List(results, id: \.self) { item in
            let alreadyPinned = isPinned(latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
            Button {
                Task { await add(item) }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.cityName(for: item))
                            .font(.headline)
                        Text(item.addressRepresentations?.cityWithContext ?? item.addressRepresentations?.regionName ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if resolvingItem == item {
                        ProgressView()
                    } else {
                        Image(systemName: alreadyPinned ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title3)
                            .foregroundStyle(alreadyPinned ? .secondary : Color.cyan)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(alreadyPinned || resolvingItem != nil)
            .listRowBackground(Color.clear)
            .accessibilityHint(alreadyPinned ? Text("Already pinned") : Text("Pins this city"))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .dismissesKeyboardOnScroll()
    }

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Suggestions", systemImage: "globe")
                    .padding(.horizontal, 20)

                ForEach(popularCities, id: \.name) { suggestion in
                    let alreadyPinned = isPinned(latitude: suggestion.lat, longitude: suggestion.lon)
                    Button {
                        onAddCity(PinnedCity(
                            name: suggestion.name, country: suggestion.localizedCountry, countryCode: suggestion.code,
                            latitude: suggestion.lat, longitude: suggestion.lon,
                            timeZoneIdentifier: suggestion.tz
                        ))
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name).font(.headline)
                                Text(suggestion.localizedCountry).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let tz = TimeZone(identifier: suggestion.tz) {
                                Text(TimeZoneMath.badge(forOffset: TimeZoneMath.offset(of: tz, at: .now)))
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: alreadyPinned ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(alreadyPinned ? .secondary : Color.cyan)
                        }
                        .padding(14)
                        .contentCard(cornerRadius: 18)
                        .contentShape(.rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(alreadyPinned)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 30)
        }
        .dismissesKeyboardOnScroll()
    }

    // MARK: - Search

    private func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = .address
        request.addressFilter = MKAddressFilter(including: .locality)
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = response.mapItems
        } catch {
            guard !Task.isCancelled else { return }
            results = []
        }
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
            errorMessage = String(localized: "WanderClock couldn't find the time zone for \(Self.cityName(for: item)). Check your connection and try again.")
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
