import SwiftUI

struct ContentView: View {
    @State private var store = CityStore.shared
    @State private var onboarding = OnboardingFlow.shared
    @State private var showingAddSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingAlarmsSheet = false
    /// A city chosen in All Alarms, opened once that sheet has gone.
    @State private var cityFromAlarms: PinnedCity?
    /// True while a city's detail is up in its own sheet (iPhone).
    @State private var showingCitySheet = false
    /// A city pinned from onboarding, opened once the search sheet has gone.
    @State private var firstCity: PinnedCity?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // The stack gives the Mac and Vision Pro window its toolbar, and the introduction its Skip button.
        NavigationStack {
            ZStack {
                ResponsiveLayoutContainer(
                    store: store,
                    showingAddSheet: $showingAddSheet,
                    showingSettingsSheet: $showingSettingsSheet,
                    showingAlarmsSheet: $showingAlarmsSheet,
                    showingCitySheet: $showingCitySheet,
                    isOnboarding: onboarding.stage == .intro
                )

                if onboarding.stage == .intro {
                    OnboardingView(
                        hasCities: !store.cities.isEmpty,
                        onChooseCity: { showingAddSheet = true },
                        onContinueWithExistingCities: {
                            if let city = store.cities.first { startAlarmStep(with: city) }
                        }
                    )
                    .frame(maxWidth: 560)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: openFirstCityIfNeeded) {
            AddCitySheet(pinnedCities: store.cities) { city in
                if store.addCity(city), onboarding.stage == .intro {
                    firstCity = city
                }
            }
        }
        #if !os(macOS)
        // While a city's sheet is up (iPhone), Settings opens over that sheet instead.
        .sheet(isPresented: Binding(
            get: { showingSettingsSheet && !showingCitySheet },
            set: { showingSettingsSheet = $0 }
        )) {
            SettingsView(store: store)
        }
        #endif
        .sheet(isPresented: Binding(
            get: { showingAlarmsSheet && !showingCitySheet },
            set: { showingAlarmsSheet = $0 }
        ), onDismiss: openCityFromAlarms) {
            AllAlarmsSheet(store: store) { city in
                cityFromAlarms = city
                showingAlarmsSheet = false
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { store.appDidBecomeActive() }
        }
        .focusedSceneValue(\.sceneActions, sceneActions)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 850, minHeight: 620)
        #endif
    }

    /// Menu commands, available while no sheet is up. Settings and Alarms wait until the introduction is done.
    /// (The Mac's Settings window has its own menu item.)
    private var sceneActions: SceneActions? {
        guard !showingAddSheet, !showingSettingsSheet, !showingAlarmsSheet, !showingCitySheet else { return nil }
        let isIntro = onboarding.stage == .intro
        return SceneActions(
            addCity: { showingAddSheet = true },
            openSettings: isIntro ? nil : { showingSettingsSheet = true },
            showAlarms: isIntro ? nil : { showingAlarmsSheet = true }
        )
    }

    private func openCityFromAlarms() {
        guard let city = cityFromAlarms else { return }
        cityFromAlarms = nil
        withAnimation(.smooth(duration: 0.5)) { store.selectedCity = city }
    }

    private func openFirstCityIfNeeded() {
        guard let city = firstCity else { return }
        firstCity = nil
        startAlarmStep(with: city)
    }

    /// Onboarding's last step: open the city on its Alarms page to ask for alarm permission.
    private func startAlarmStep(with city: PinnedCity) {
        withAnimation(.smooth(duration: 0.4)) { onboarding.didPinFirstCity() }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.smooth(duration: 0.55)) { store.selectedCity = city }
        }
    }
}

#Preview {
    ContentView()
}
