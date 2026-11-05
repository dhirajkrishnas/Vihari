import SwiftUI

struct ContentView: View {
    @State private var store = CityStore.shared
    @State private var onboarding = OnboardingFlow.shared
    @State private var showingAddSheet = false
    @State private var showingSettingsSheet = false
    /// A city pinned from onboarding, opened once the search sheet has gone.
    @State private var firstCity: PinnedCity?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ResponsiveLayoutContainer(
                store: store,
                showingAddSheet: $showingAddSheet,
                showingSettingsSheet: $showingSettingsSheet,
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
        .sheet(isPresented: $showingAddSheet, onDismiss: openFirstCityIfNeeded) {
            AddCitySheet(pinnedCities: store.cities) { city in
                if store.addCity(city), onboarding.stage == .intro {
                    firstCity = city
                }
            }
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView(store: store)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { store.appDidBecomeActive() }
        }
        .focusedSceneValue(\.sceneActions, sceneActions)
        .tint(.cyan)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 850, minHeight: 620)
        #endif
    }

    /// Menu commands, available while no sheet is up. Settings waits until the introduction is done.
    private var sceneActions: SceneActions? {
        guard !showingAddSheet, !showingSettingsSheet else { return nil }
        return SceneActions(
            addCity: { showingAddSheet = true },
            openSettings: onboarding.stage == .intro ? nil : { showingSettingsSheet = true }
        )
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
