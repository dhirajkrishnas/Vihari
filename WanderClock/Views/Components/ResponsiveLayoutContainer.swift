import SwiftUI

struct ResponsiveLayoutContainer: View {
    @Bindable var store: CityStore
    @Binding var showingAddSheet: Bool
    @Binding var showingSettingsSheet: Bool
    /// While onboarding runs, only the globe shows; the intro panel sits over it.
    var isOnboarding = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One motion for every globe ⇄ city change, so panel, cards and camera move together.
    private let panelAnimation = Animation.smooth(duration: 0.55)

    /// The city cards' scroll position. It's kept here because the cards leave while a city is open.
    @State private var cardsPosition = ScrollPosition(idType: PinnedCity.ID.self)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                StarryBackgroundView()

                if isWide(geometry.size) {
                    wideLayout(geometry)
                } else {
                    compactLayout(geometry.size)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: store.selectedCityID)
    }

    private func isWide(_ size: CGSize) -> Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular || size.width > 700
        #else
        return size.width > 700
        #endif
    }

    private func select(_ city: PinnedCity?) {
        if city == nil, OnboardingFlow.shared.stage == .alarmPermission {
            OnboardingFlow.shared.finish()
        }
        withAnimation(panelAnimation) { store.selectedCity = city }
    }

    private var settingsButton: some View {
        GlassIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {
            showingSettingsSheet = true
        }
    }

    // MARK: - iPad / Mac / wide split layout

    private func wideLayout(_ geometry: GeometryProxy) -> some View {
        let size = geometry.size
        // The city list's pane along the trailing edge. A city's detail opens in the same place.
        let paneWidth = size.width * 0.48
        let cityIsOpen = store.selectedCity != nil

        // Each layer that comes and goes has a zIndex: a view leaving a ZStack without one can be
        // drawn behind the others, so it seems to vanish instead of sliding away.
        return ZStack(alignment: .trailing) {
            // The globe has the whole window. It's framed beside the pane and runs on underneath it,
            // so while a city is open its map reaches the far edge, behind the detail.
            GlobeView(
                cities: store.cities,
                selectedCity: store.selectedCity,
                // Measured from the window's edge, since the pane's backdrop runs into the safe area.
                trailingPaneWidth: paneWidth + geometry.safeAreaInsets.trailing,
                showsTrailingPane: !isOnboarding,
                onSelectCity: select
            )
            .ignoresSafeArea()

            if !isOnboarding {
                settingsButton
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, paneWidth)
                    .transition(.opacity)
                    .zIndex(1)

                // The city list, with a city's detail over it while one is open. The list stays
                // alive underneath, so it's still scrolled to the same place when the city closes.
                ZStack {
                    // The list's backdrop fades away while a city is open, so the map fills the window.
                    Color.black
                        .ignoresSafeArea()
                        .opacity(cityIsOpen ? 0 : 1)

                    cityList
                        .opacity(cityIsOpen ? 0 : 1)
                        .disabled(cityIsOpen)
                        .accessibilityHidden(cityIsOpen)

                    if let selected = store.selectedCity {
                        detailView(for: selected)
                            .padding(12)
                            .transition(slide(from: .trailing))
                            .zIndex(1)
                    }
                }
                .frame(width: paneWidth)
                .transition(slide(from: .trailing))
                .zIndex(2)
            }
        }
    }

    private var cityList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cities")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)

                ForEach(store.cities) { city in
                    LiquidGlassCityCard(
                        city: city,
                        weather: store.weatherState(for: city),
                        alarms: store.alarms(for: city),
                        style: .inline,
                        onSelect: { select(city) }
                    )
                    .contextMenu { unpinButton(for: city) }
                }

                AddCityCardButton(style: .inline) { showingAddSheet = true }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - iPhone single-screen layout

    private func compactLayout(_ size: CGSize) -> some View {
        let totalHeight = size.height
        // Cards float just above the bottom edge, inset the same as from the sides.
        let cardsHeight = LiquidGlassCityCard.floatingSize(for: dynamicTypeSize).height + 2 * CityCardsCarouselView.edgeInset
        let panelHeight = totalHeight * 0.64
        // The globe sits above the cards, or above the intro panel while onboarding.
        // (The globe ignores the safe area, so this is measured from the screen's bottom edge.)
        let orbitBottomInset = isOnboarding ? totalHeight * 0.42 : cardsHeight

        return ZStack(alignment: .top) {
            GlobeView(
                cities: store.cities,
                selectedCity: store.selectedCity,
                orbitBottomInset: orbitBottomInset,
                attributionBottomInset: cardsHeight,
                detailBottomInset: panelHeight,
                fillsScreen: true,
                onSelectCity: select
            )
                .ignoresSafeArea()

            // As in the wide layout, each layer that comes and goes has a zIndex, so it stays in
            // front of the globe while it animates away.
            if store.selectedCity == nil && !isOnboarding {
                HStack {
                    Spacer()
                    settingsButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.opacity)
                .zIndex(1)
            }

            // Bottom quarter: the city cards, ending with an Add City card
            if store.selectedCity == nil && !isOnboarding {
                VStack {
                    Spacer()
                    CityCardsCarouselView(
                        cities: store.cities,
                        position: $cardsPosition,
                        weatherProvider: { store.weatherState(for: $0) },
                        alarmsProvider: { store.alarms(for: $0) },
                        onSelectCity: select,
                        onUnpinCity: { store.removeCity($0) },
                        onAddCityTap: { showingAddSheet = true }
                    )
                    .frame(height: cardsHeight)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(rise(by: cardsHeight).combined(with: .opacity))
                .zIndex(2)
            }

            // City detail rises from the bottom when a city is selected
            if let selected = store.selectedCity {
                VStack {
                    Spacer()
                    detailView(for: selected)
                        .frame(height: panelHeight)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(rise(by: panelHeight))
                .zIndex(3)
            }
        }
    }

    // MARK: - Shared

    private func detailView(for city: PinnedCity) -> some View {
        CityDetailView(
            city: city,
            weather: store.weatherState(for: city),
            alarms: store.alarms(for: city),
            initialTab: OnboardingFlow.shared.stage == .alarmPermission ? .alarms : .weather,
            onClose: { select(nil) },
            onSetAlarmEnabled: { store.setAlarm($0, enabled: $1) },
            onDeleteAlarm: { store.deleteAlarm($0) },
            onSaveAlarm: { alarm in
                if store.alarms.contains(where: { $0.id == alarm.id }) {
                    store.updateAlarm(alarm)
                } else {
                    store.addAlarm(alarm)
                }
            },
            onRetryWeather: { store.loadWeather(for: city, force: true) },
            onDeleteCity: { withAnimation(panelAnimation) { store.removeCity(city) } }
        )
        .id(city.id)
    }

    /// Panels slide in from an edge, or fade when Reduce Motion is on.
    private func slide(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge)
    }

    /// Bottom panels rise by their own height. Moving the full-height stack they sit in instead
    /// would keep them below the screen for the first part of the motion, so they'd start late.
    private func rise(by height: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .offset(y: height)
    }

    private func unpinButton(for city: PinnedCity) -> some View {
        Button(role: .destructive) {
            withAnimation { store.removeCity(city) }
        } label: {
            Label("Unpin \(city.name)", systemImage: "pin.slash")
        }
    }
}
