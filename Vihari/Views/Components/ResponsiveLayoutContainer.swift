import SwiftUI

struct ResponsiveLayoutContainer: View {
    @Bindable var store: CityStore
    @Binding var showingAddSheet: Bool
    @Binding var showingSettingsSheet: Bool
    @Binding var showingAlarmsSheet: Bool
    /// Set while a city's detail is up as a sheet (iPhone). Other sheets can't open over it.
    @Binding var showingCitySheet: Bool
    /// While onboarding runs, only the globe shows; the intro panel sits over it.
    var isOnboarding = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// A city with alarms waiting for the person to confirm it should be unpinned.
    @State private var cityPendingRemoval: PinnedCity?

    var body: some View {
        GeometryReader { geometry in
            let wide = isWide(geometry.size)
            ZStack {
                StarryBackgroundView()

                if geometry.size.width > 0 && geometry.size.height > 0 {
                    if wide {
                        wideLayout(geometry)
                    } else {
                        compactLayout(geometry)
                    }
                }
            }
            .onChange(of: wide, initial: true) { _, wide in isCompact = !wide }
            .onChange(of: Self.screenHeight(geometry), initial: true) { _, height in
                citySheetHeight = Self.citySheetHeight(screenHeight: height)
            }
        }
        .sensoryFeedback(.selection, trigger: store.selectedCityID)
        #if os(iOS)
        // Over the globe, the controls float as glass, as they do over the map in Maps. The system
        // bar would lay a band of blur behind the city's name and set it in its own small title
        // font. It still shows during the introduction, for its Skip button.
        .toolbar(isOnboarding ? .automatic : .hidden, for: .navigationBar)
        // A plain inset, not `safeAreaBar`: a bar would lay the same blur over the map's top edge.
        .safeAreaInset(edge: .top, spacing: 0) {
            if !isOnboarding { topBar }
        }
        #else
        .toolbar { navigationBar }
        .navigationTitle(store.selectedCity?.name ?? "Vihari")
        #if os(macOS)
        // The globe runs up under the window's toolbar.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        #endif
        .confirmationDialog(
            Text("Unpin \(cityPendingRemoval?.name ?? "")?"),
            isPresented: Binding(get: { cityPendingRemoval != nil }, set: { if !$0 { cityPendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: cityPendingRemoval
        ) { city in
            Button("Unpin City", role: .destructive) {
                withAnimation(panelAnimation) { store.removeCity(city) }
            }
        } message: { city in
            Text("Its \(store.alarms(for: city).count) alarms will be deleted too.")
        }
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

    /// Unpins a city straight away, or asks first when that would delete its alarms.
    private func requestUnpin(_ city: PinnedCity) {
        if store.alarms(for: city).isEmpty {
            withAnimation(panelAnimation) { store.removeCity(city) }
        } else {
            cityPendingRemoval = city
        }
    }

    // MARK: - Top bar

    #if os(iOS)
    /// The controls over the globe: Back and the open city's name at the leading end, and at the
    /// trailing end Settings, which shares its glass with All Alarms on the globe.
    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if let city = store.selectedCity {
                    GlassIconButton(systemImage: "chevron.backward", accessibilityLabel: "Back to Cities") {
                        select(nil)
                    }
                    .keyboardShortcut(.cancelAction)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))

                    Text(city.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(.white)
                        // Keeps the name legible over bright imagery, with no band of blur behind it.
                        .shadow(color: .black.opacity(0.6), radius: 10, y: 1)
                        .accessibilityAddTraits(.isHeader)
                        .id(city.id)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)

                GlassIconGroup {
                    if store.selectedCity == nil {
                        Button("Alarms", systemImage: "alarm") { showingAlarmsSheet = true }
                            .transition(.opacity)
                    }
                    Button("Settings", systemImage: "gearshape") { showingSettingsSheet = true }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
    #else
    /// The window's toolbar: Back beside the navigation title, and at the trailing end Settings,
    /// grouped with All Alarms on the globe. The system gives the buttons their glass.
    @ToolbarContentBuilder
    private var navigationBar: some ToolbarContent {
        if !isOnboarding {
            if store.selectedCity != nil {
                ToolbarItem(placement: .navigation) {
                    Button { select(nil) } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Back to Cities")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if store.selectedCity == nil {
                    Button { showingAlarmsSheet = true } label: {
                        Label("Alarms", systemImage: "alarm")
                    }
                }
                settingsButton
            }
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        #if os(macOS)
        // The Mac keeps settings in their own window (Vihari > Settings…).
        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        #else
        Button { showingSettingsSheet = true } label: {
            Label("Settings", systemImage: "gearshape")
        }
        #endif
    }
    #endif

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
                detailTopInset: geometry.safeAreaInsets.top + 12,
                // Measured from the window's edge, since the map runs under the safe area there.
                trailingPaneWidth: paneWidth + geometry.safeAreaInsets.trailing,
                showsTrailingPane: !isOnboarding,
                onSelectCity: select
            )
            .ignoresSafeArea()

            if !isOnboarding {
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
        }
    }

    /// The pinned cities, under a header with the Add button. Swipe a city toward the leading
    /// edge (or use its context menu) to unpin it.
    private var cityList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Cities")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                GlassIconButton(systemImage: "plus", accessibilityLabel: "Add City", prominent: true) {
                    showingAddSheet = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if store.cities.isEmpty {
                ContentUnavailableView {
                    Label("No Cities", systemImage: "globe")
                } description: {
                    Text("Pin a city to see its time, weather and alarms.")
                } actions: {
                    Button("Add City") { showingAddSheet = true }
                        .adaptiveGlassButtonStyle(prominent: true)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.cities) { city in
                            LiquidGlassCityCard(
                                city: city,
                                weather: store.weatherState(for: city),
                                alarms: store.alarms(for: city),
                                style: .inline,
                                onSelect: { select(city) }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { requestUnpin(city) } label: {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                            }
                            .contextMenu { unpinButton(for: city) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 30)
                }
                .swipeActionsContainer()
                .scrollIndicators(.hidden)
            }
        }
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
                detailTopInset: geometry.safeAreaInsets.top + 8,
                fillsScreen: true,
                onSelectCity: select
            )
                .ignoresSafeArea()

            // As in the wide layout, each layer that comes and goes has a zIndex, so it stays in
            // front of the globe while it animates away.

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
                        onUnpinCity: requestUnpin,
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
                // Only one sheet can be up per presenter, so Settings opens over this one.
                .sheet(isPresented: $showingSettingsSheet) { SettingsView(store: store) }
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
            onSaveAlarm: { store.saveAlarm($0) },
            onRetryWeather: { store.loadWeather(for: city, force: true) }
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
            requestUnpin(city)
        } label: {
            Label("Unpin \(city.name)", systemImage: "pin.slash")
        }
    }
}
