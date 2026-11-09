import Foundation
import AppIntents
import SwiftUI

struct SetCityAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Set City Alarm"
    static let description = IntentDescription("Sets an alarm that rings at a time in a pinned city's local time, wherever you are.")

    @Parameter(title: "City")
    var city: PinnedCityEntity

    @Parameter(title: "Time", description: "The time in the city's local time.", kind: .time)
    var alarmTime: Date

    @Parameter(
        title: "Date",
        description: "The day it rings, on the city's calendar. If it repeats, the first day it can ring. Leave it empty for the next time it comes round.",
        kind: .date
    )
    var date: Date?

    @Parameter(title: "Label", default: "Alarm")
    var label: String

    @Parameter(title: "Repeat on Weekdays", default: false)
    var repeatsOnWeekdays: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set an alarm for \(\.$alarmTime) in \(\.$city)") {
            \.$date
            \.$label
            \.$repeatsOnWeekdays
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let pinned = city.city else { throw CityIntentError.cityNotFound }

        // Siri hands us a wall-clock time in the device's zone; keep its hour and minute as city time.
        let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let alarm = CityAlarm(
            cityId: pinned.id,
            cityName: pinned.name,
            timeZoneIdentifier: pinned.timeZoneIdentifier,
            hour: parts.hour ?? 8,
            minute: parts.minute ?? 0,
            label: trimmedLabel.isEmpty ? String(localized: "\(pinned.name) Alarm") : trimmedLabel,
            repeatSchedule: repeatsOnWeekdays ? .weekdays : .never,
            // The day Siri hears is taken as that day in the city, as the time is.
            scheduledDay: date.map { CityDay($0, in: .current) }
        )
        if !alarm.repeatSchedule.repeats, let ring = alarm.oneTimeRing(after: .now), ring <= .now {
            throw CityIntentError.alarmTimeHasPassed(cityName: pinned.name)
        }
        CityStore.shared.addAlarm(alarm)
        await AlarmScheduler.shared.waitUntilIdle()
        await AlarmScheduler.shared.refreshAuthorization()

        let cityTime = alarm.formattedCityTime
        let context = alarm.travelerContextSummary()
        // Don't claim the alarm will ring if alarms aren't allowed yet.
        let dialog: IntentDialog = AlarmScheduler.shared.authorization == .authorized
            ? "Alarm set for \(cityTime) \(pinned.name) time. That’s \(context)."
            : "I saved an alarm for \(cityTime) \(pinned.name) time, but Vihari isn’t allowed to ring alarms yet. Open Vihari to allow them."
        return .result(
            dialog: dialog,
            view: CityAlarmSnippetView(
                cityName: pinned.name,
                alarmLabel: alarm.label,
                cityTimeFormatted: cityTime,
                travelerTimeFormatted: context
            )
        )
    }
}
