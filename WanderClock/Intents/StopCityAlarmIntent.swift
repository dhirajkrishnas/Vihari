#if os(iOS)
import Foundation
import AppIntents
import AlarmKit

/// Runs when someone taps Stop on a ringing WanderClock alarm. The system runs it in the app
/// even when the app isn't open, which makes it the moment to switch off a one-time alarm and
/// queue the next rings, so repeating alarms keep ringing however long the app stays closed.
struct StopCityAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Alarm"
    static let description = IntentDescription("Stops a ringing WanderClock alarm.")
    static let isDiscoverable = false

    @Parameter(title: "Alarm")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Stop the ring first, before anything that could take time.
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
        }
        await CityStore.shared.refreshAlarmSchedule()
        return .result()
    }
}
#endif
