import SwiftUI

@main
struct WanderClockApp: App {
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    init() {
        // Set up alarms first, so a notification action that launched the app reaches its handler.
        _ = AlarmScheduler.shared
        // Listen for tip transactions from launch, so ones that finish later (Ask to Buy, an
        // interrupted purchase) are completed and acknowledged.
        _ = DonationStore.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands { WanderClockCommands() }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif

        #if os(iOS)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await BackgroundRefresh.schedule() } }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(store: CityStore.shared)
                .frame(width: 600, height: 700)
        }
        #endif
    }
}
