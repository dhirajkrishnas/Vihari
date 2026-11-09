import Foundation
import AppIntents

struct VihariShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetCityTimeIntent(),
            phrases: [
                "What time is it in \(\.$city) in \(.applicationName)",
                "Check the time in \(\.$city) with \(.applicationName)",
                "\(.applicationName) time in \(\.$city)"
            ],
            shortTitle: "City Time",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: SetCityAlarmIntent(),
            phrases: [
                "Set an alarm in \(\.$city) time with \(.applicationName)",
                "Set a \(\.$city) alarm in \(.applicationName)"
            ],
            shortTitle: "City Alarm",
            systemImageName: "alarm"
        )
        AppShortcut(
            intent: GetCityWeatherIntent(),
            phrases: [
                "What's the weather in \(\.$city) in \(.applicationName)",
                "Check the weather in \(\.$city) with \(.applicationName)"
            ],
            shortTitle: "City Weather",
            systemImageName: "cloud.sun"
        )
    }
}
