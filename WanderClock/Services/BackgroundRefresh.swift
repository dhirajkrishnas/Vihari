#if os(iOS)
import Foundation
import BackgroundTasks

/// Asks iOS to wake the app now and then, so the queue of upcoming alarm rings stays topped up
/// even if the app isn't opened for weeks. A safety net: stopping an alarm tops it up too.
enum BackgroundRefresh {
    static let identifier = "com.dhirajkrishnasimhadri.WanderClock.refresh"

    static func schedule() async {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(12 * 3600)
        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        } catch {
            // Not available (for example in the Simulator, or with Background App Refresh off).
        }
    }

    static func run() async {
        await schedule()
        await CityStore.shared.refreshAlarmSchedule()
    }
}
#endif
