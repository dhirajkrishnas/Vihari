import SwiftUI

@main
struct WanderClockApp: App {
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    init() {
        // Set up alarms first, so a notification action that launched the app reaches its handler.
        _ = AlarmScheduler.shared
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
    }
}
