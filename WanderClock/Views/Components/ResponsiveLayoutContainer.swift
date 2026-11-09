import SwiftUI

struct ResponsiveLayoutContainer: View {
    @Bindable var store: CityStore
    @Binding var showingAddSheet: Bool
    @Binding var showingSettingsSheet: Bool
    /// Set while a city's detail is up as a sheet (iPhone). Other sheets can't open over it.
    @Binding var showingCitySheet: Bool
    /// While onboarding runs, only the globe shows; the intro panel sits over it.
    var isOnboarding = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The height of the open city's name over the map.
    @ScaledMetric(relativeTo: .largeTitle) private var headingHeight: CGFloat = 41

    /// One motion for every globe ⇄ city change in this layout's own views.
    private let panelAnimation = Animation.smooth(duration: 0.5)

    /// The city cards' scroll position. It's kept here because the layout can be rebuilt.
    @State private var cardsPosition = ScrollPosition(idType: PinnedCity.ID.self)
    /// True while the single-column layout shows, where a city opens in a sheet.
    @State private var isCompact = false
    /// The city sheet's resting height, for a screen of the current height.
    @State private var citySheetHeight: CGFloat = 480
    /// The city last shown in the sheet. It stays set after the city closes, so the sheet keeps
    /// its content while it slides away.
    @State private var sheetCity: PinnedCity?

    var body: some View {
        GeometryReader { geometry in
            let wide = isWide(geometry.size)
            ZStack {
                StarryBackgroundView()

                if wide {
                    wideLayout(geometry)
                } else {
                    compactLayout(geometry)
                }
            }
            .onChange(of: wide, initial: true) { _, wide in isCompact = !wide }
            .onChange(of: Self.screenHeight(geometry), initial: true) { _, height in
                citySheetHeight = Self.citySheetHeight(screenHeight: height)
            }
        }
        .sensoryFeedback(.selection, trigger: store.selectedCityID)
        #if os(iOS)
        .sheet(isPresented: citySheetIsPresented) { citySheet }
        .onChange(of: usesCitySheet, initial: true) { _, presented in showingCitySheet = presented }
        .onChange(of: store.selectedCity, initial: true) { _, city in
            if let city { sheetCity = city }
        }
        #endif
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

    /// The open city's name, as a heading over the map at the top left.
    private func cityHeading(_ city: PinnedCity) -> some View {
        Text(city.name)
            .font(.largeTitle.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            // Keeps it readable over bright imagery.
            .shadow(color: .black.opacity(0.6), radius: 12, y: 2)
            .accessibilityAddTraits(.isHeader)
            .allowsHitTesting(false)
            .id(city.id)
            .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
    }

    // MARK: - iPad / Mac / wide split layout

    private func wideLayout(_ geometry: GeometryProxy) -> some View {
        let size = geometry.size
        // The pane along the trailing edge: the city list, or a city's detail in its place.
        let paneWidth = size.width * 0.48
        let cityIsOpen = store.selectedCity != nil

        // Each layer that comes and goes has a zIndex: a view leaving a ZStack without one can be
        // drawn behind the others, so it seems to vanish instead of sliding away.
        return ZStack(alignment: .trailing) {
            // The globe has the whole window. It's framed beside the pane, and while a city is open
            // its map reaches under the pane to the window's far edge, behind the glass.
            GlobeView(
                cities: store.cities,
                selectedCity: store.selectedCity,
                detailTopInset: geometry.safeAreaInsets.top + 16 + headingHeight,
                // Measured from the window's edge, since the map runs under the safe area there.
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

                // One glass panel holds the list, and a city's detail slides in over it like a pushed
                // page. The list stays alive underneath, so it's still scrolled to the same place
                // when the city closes.
                ZStack {
                    cityList
                        .offset(x: cityIsOpen && !reduceMotion ? -paneWidth * 0.3 : 0)
                        .opacity(cityIsOpen ? 0 : 1)
                        .disabled(cityIsOpen)
                        .accessibilityHidden(cityIsOpen)

                    if let selected = store.selectedCity {
                        detailView(for: selected, showsBackground: false)
                            .transition(slide(from: .trailing))
                            .zIndex(1)
                    }
                }
                .clipShape(.rect(cornerRadius: Self.panelCornerRadius, style: .continuous))
                .background { Color.clear.floatingGlass(cornerRadius: Self.panelCornerRadius) }
                .padding(12)
                .frame(width: paneWidth)
                .transition(slide(from: .trailing))
                .zIndex(2)
            }

            if let city = store.selectedCity {
                cityHeading(city)
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // Clear of the Settings button at the pane's edge.
                    .padding(.trailing, paneWidth + 84)
                    .zIndex(3)
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
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - iPhone single-screen layout

    private func compactLayout(_ geometry: GeometryProxy) -> some View {
        let totalHeight = geometry.size.height
        // Cards float just above the bottom edge, inset the same as from the sides.
        let cardsHeight = LiquidGlassCityCard.floatingSize(for: dynamicTypeSize).height + 2 * CityCardsCarouselView.edgeInset
        // The globe sits above the cards, or above the intro panel while onboarding.
        // (The globe ignores the safe area, so this is measured from the screen's bottom edge.)
        let orbitBottomInset = isOnboarding ? totalHeight * 0.42 : cardsHeight
        #if os(iOS)
        let detailHeight = Self.citySheetVisibleHeight(sheetHeight: citySheetHeight)
        #else
        let detailHeight = totalHeight * 0.64
        #endif

        return ZStack(alignment: .top) {
            // The map fills the screen in every view. While a city is open it runs on behind the sheet.
            GlobeView(
                cities: store.cities,
                selectedCity: store.selectedCity,
                orbitBottomInset: orbitBottomInset,
                attributionBottomInset: cardsHeight,
                detailBottomInset: detailHeight,
                detailTopInset: geometry.safeAreaInsets.top + 8 + headingHeight,
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

            // Bottom: the city cards, ending with an Add City card. On iPhone they stay (faded out)
            // while a city's sheet is up, so they're back, still scrolled to the same card, the
            // moment it closes.
            if !isOnboarding && (Self.opensCitiesInSheet || store.selectedCity == nil) {
                VStack {
                    Spacer()
                    CityCardsCarouselView(
                        cities: store.cities,
                        position: $cardsPosition,
                        weatherProvider: { store.weatherState(for: $0) },
                        alarmsProvider: { store.alarms(for: $0) },
                        onSelectCity: select,
                        onUnpinCity: { store.removeCity($0) },
                        onAddCityTap: { showingAddSheet = true },
                        isUnderSheet: Self.opensCitiesInSheet && store.selectedCity != nil
                    )
                    .frame(height: cardsHeight)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(rise(by: cardsHeight).combined(with: .opacity))
                .zIndex(2)
            }

            #if !os(iOS)
            // Elsewhere the city's detail rises from the bottom when a city is selected.
            if let selected = store.selectedCity {
                VStack {
                    Spacer()
                    detailView(for: selected)
                        .frame(height: detailHeight)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(rise(by: detailHeight))
                .zIndex(3)
            }
            #endif

            if let city = store.selectedCity {
                cityHeading(city)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(4)
            }
        }
    }

    // MARK: - City sheet (iPhone)

    #if os(iOS)
    private static let opensCitiesInSheet = true

    private var usesCitySheet: Bool {
        isCompact && store.selectedCity != nil
    }

    private var citySheetIsPresented: Binding<Bool> {
        Binding(
            get: { usesCitySheet },
            set: { presented in
                // Swiped down: close the city. A sheet that closes because the layout widened (the
                // phone turned) leaves the city open beside the list instead.
                if !presented, isCompact, store.selectedCity != nil { select(nil) }
            }
        )
    }

    /// The open city's detail in a native sheet. It rests partway up, leaving the city in view on
    /// the map above it, and can be pulled up to full height. The map stays live behind it.
    @ViewBuilder
    private var citySheet: some View {
        if let city = store.selectedCity ?? sheetCity {
            let resting = PresentationDetent.height(citySheetHeight)
            detailView(for: city, showsBackground: false)
                .presentationDetents([resting, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: resting))
        }
    }

    /// How far up the screen the resting sheet reaches, from the bottom edge. Measured on iOS 27:
    /// a resting sheet floats 8 pt above the bottom edge and stands 13 pt taller than its detent.
    private static func citySheetVisibleHeight(sheetHeight: CGFloat) -> CGFloat {
        sheetHeight + 21
    }
    #else
    private static let opensCitiesInSheet = false
    #endif

    /// How tall the resting city sheet is.
    private static func citySheetHeight(screenHeight: CGFloat) -> CGFloat {
        (screenHeight * 0.55).rounded()
    }

    private static func screenHeight(_ geometry: GeometryProxy) -> CGFloat {
        geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
    }

    // MARK: - Shared

    private static let panelCornerRadius: CGFloat = 34

    private func detailView(for city: PinnedCity, showsBackground: Bool = true) -> some View {
        CityDetailView(
            city: city,
            weather: store.weatherState(for: city),
            alarms: store.alarms(for: city),
            initialTab: OnboardingFlow.shared.stage == .alarmPermission ? .alarms : .weather,
            showsBackground: showsBackground,
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
