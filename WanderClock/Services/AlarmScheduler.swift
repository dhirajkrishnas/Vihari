import Foundation
import Observation
import SwiftUI
import UserNotifications
import os
#if os(iOS)
import AlarmKit
#endif

/// Turns `CityAlarm`s into system alarms.
///
/// City alarms ring at a city's local time, which is a different moment on the device each
/// time you travel or a DST change happens in either place. So instead of a device-relative
/// repeating alarm, every upcoming ring is scheduled as its own exact, absolute moment.
/// `reconcile(with:)` keeps that queue topped up and in step with the user's alarms.
///
/// The queue is topped up whenever the app becomes active, whenever a ringing alarm is
/// stopped (even with the app closed, through `StopCityAlarmIntent`), and by background refresh.
///
/// - iPhone / iPad: AlarmKit, so alarms break through Silent and Focus like the Clock app.
/// - Mac / Vision Pro: local notifications.
@Observable
final class AlarmScheduler {
    static let shared = AlarmScheduler()

    enum Authorization: Equatable {
        case notDetermined, authorized, denied
    }

    private(set) var authorization: Authorization = .notDetermined

    /// Called when a system alarm goes away (it rang and was stopped) or permission changes.
    @ObservationIgnored var onSystemAlarmsChanged: (() -> Void)?

    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    /// A permission request asked for by a reconcile that a newer one replaced before it ran.
    @ObservationIgnored private var wantsPermission = false
    @ObservationIgnored private var observerTasks: [Task<Void, Never>] = []
    private let log = Logger(subsystem: "com.dhirajkrishnasimhadri.WanderClock", category: "Alarms")
    private let notificationDelegate = AlarmNotificationDelegate()

    /// How far ahead rings are queued, and how many are queued at most across all alarms
    /// (the soonest first). Notifications are capped by the system at 64 per app; a few are
    /// left free for snoozes.
    private let horizonDays = 21
    #if os(iOS)
    private let queueLimit = 64
    #else
    private let queueLimit = 58
    #endif

    private init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        AlarmNotificationDelegate.registerCategories()
        #if os(iOS)
        authorization = Self.map(AlarmManager.shared.authorizationState)
        #endif
        observeSystemAlarms()
        Task { await refreshAuthorization() }
    }

    // MARK: - Authorization

    func refreshAuthorization() async {
        #if os(iOS)
        authorization = Self.map(AlarmManager.shared.authorizationState)
        #else
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        default: .notDetermined
        }
        #endif
    }

    /// Asks for permission in context — only when the user switches an alarm on.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorization()
        if authorization == .authorized { return true }
        guard authorization == .notDetermined else { return false }
        #if os(iOS)
        do {
            authorization = Self.map(try await AlarmManager.shared.requestAuthorization())
        } catch {
            log.error("AlarmKit authorization failed: \(error.localizedDescription)")
            authorization = .denied
        }
        #else
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorization = granted ? .authorized : .denied
            AlarmNotificationDelegate.registerCategories()
        } catch {
            authorization = .denied
        }
        #endif
        return authorization == .authorized
    }

    // MARK: - Scheduling

    /// Brings the system schedule in line with `alarms`. Safe to call often: calls run one at
    /// a time, and a newer call replaces one that hasn't finished.
    func reconcile(with alarms: [CityAlarm], requestPermission: Bool) {
        if requestPermission { wantsPermission = true }
        let previous = reconcileTask
        previous?.cancel()
        reconcileTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            if wantsPermission, alarms.contains(where: \.isEnabled) {
                wantsPermission = false
                await requestAuthorizationIfNeeded()
            }
            await refreshAuthorization()
            guard !Task.isCancelled, authorization == .authorized else { return }
            await apply(desired: desiredOccurrences(for: alarms))
        }
    }

    /// Finishes once the latest reconcile has finished.
    func waitUntilIdle() async {
        while let task = reconcileTask {
            await task.value
            if task == reconcileTask { return }
        }
    }

    /// The upcoming rings of every enabled alarm, soonest first, so if the system runs out
    /// of room it's the furthest ones that wait.
    private func desiredOccurrences(for alarms: [CityAlarm]) -> [Occurrence] {
        let now = Date.now
        let all = alarms.filter(\.isEnabled).flatMap { alarm in
            alarm.upcomingTriggerDates(from: now, limit: horizonDays, horizonDays: horizonDays)
                .map { Occurrence(alarm: alarm, fireDate: $0) }
        }
        return Array(all.sorted { $0.fireDate < $1.fireDate }.prefix(queueLimit))
    }

    #if os(iOS)
    private typealias Metadata = WanderClockAlarmMetadata

    private func apply(desired: [Occurrence]) async {
        let manager = AlarmManager.shared
        let live = (try? manager.alarms) ?? []
        let liveIDs = Set(live.map(\.id))
        let desiredIDs = Set(desired.map(\.systemID))

        // A ringing alarm is left alone; it ends when it's stopped.
        for alarm in live where !desiredIDs.contains(alarm.id) && alarm.state != .alerting {
            try? manager.cancel(id: alarm.id)
        }

        for occurrence in desired where !liveIDs.contains(occurrence.systemID) {
            guard !Task.isCancelled else { return }
            let alarm = occurrence.alarm
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: alarm.alertTitle))
            let attributes = AlarmAttributes<Metadata>(
                presentation: AlarmPresentation(alert: alert),
                metadata: Metadata(alarmID: alarm.id, cityName: alarm.cityName, cityTime: alarm.formattedCityTime),
                tintColor: .cyan
            )
            do {
                _ = try await manager.schedule(
                    id: occurrence.systemID,
                    configuration: .alarm(
                        schedule: .fixed(occurrence.fireDate),
                        attributes: attributes,
                        stopIntent: StopCityAlarmIntent(alarmID: occurrence.systemID)
                    )
                )
            } catch {
                log.error("Could not schedule \(alarm.label, privacy: .public): \(error.localizedDescription)")
                if case AlarmManager.AlarmError.maximumLimitReached = error { return }
            }
        }
    }

    private func observeSystemAlarms() {
        observerTasks.append(Task { [weak self] in
            var previous: Set<UUID>?
            for await alarms in AlarmManager.shared.alarmUpdates {
                let ids = Set(alarms.map(\.id))
                // Rings disappear once stopped; that's when one-time alarms retire and the queue
                // needs topping up. New rings appearing are this app's own scheduling.
                if let previous, !previous.isSubset(of: ids) { self?.onSystemAlarmsChanged?() }
                previous = ids
            }
        })
        observerTasks.append(Task { [weak self] in
            for await state in AlarmManager.shared.authorizationUpdates {
                guard let self else { return }
                let wasAuthorized = authorization == .authorized
                authorization = Self.map(state)
                // Allowed in Settings later: schedule everything that's waiting.
                if !wasAuthorized, authorization == .authorized { onSystemAlarmsChanged?() }
            }
        })
    }

    private static func map(_ state: AlarmManager.AuthorizationState) -> Authorization {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }
    #else
    private func apply(desired: [Occurrence]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .filter { $0.content.categoryIdentifier == AlarmNotificationDelegate.category && !$0.identifier.hasPrefix(AlarmNotificationDelegate.snoozePrefix) }
        let pendingIDs = Set(pending.map(\.identifier))
        let desiredIDs = Set(desired.map(\.systemID.uuidString))

        let stale = pendingIDs.subtracting(desiredIDs)
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(stale)) }

        // A calendar trigger names the exact moment, so it stays right across sleep and clock changes.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        for occurrence in desired where !pendingIDs.contains(occurrence.systemID.uuidString) {
            guard !Task.isCancelled else { return }
            let alarm = occurrence.alarm
            let content = UNMutableNotificationContent()
            content.title = alarm.label
            content.subtitle = String(localized: "\(alarm.formattedCityTime) in \(alarm.cityName)")
            content.sound = .default
            content.categoryIdentifier = AlarmNotificationDelegate.category
            let moment = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: occurrence.fireDate)
            let request = UNNotificationRequest(
                identifier: occurrence.systemID.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: moment, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                log.error("Could not schedule \(alarm.label, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    private func observeSystemAlarms() {}
    #endif
}

/// One future ring of an alarm. Its system ID is derived from the alarm's settings and the
/// ring time, so an unchanged occurrence keeps its ID and isn't needlessly rescheduled.
private nonisolated struct Occurrence {
    let alarm: CityAlarm
    let fireDate: Date

    var systemID: UUID {
        // The version prefix changes every ID when the way rings are scheduled changes.
        let seed = "v2|\(alarm.id.uuidString)|\(Int(fireDate.timeIntervalSince1970))|\(alarm.label)|\(alarm.cityName)"
        return StableUUID.make(from: seed)
    }
}

/// Builds a deterministic UUID from a string (FNV-1a based; not for security use).
nonisolated enum StableUUID {
    static func make(from string: String) -> UUID {
        var a: UInt64 = 0xcbf29ce484222325
        var b: UInt64 = 0x84222325cbf29ce4
        for byte in string.utf8 {
            a = (a ^ UInt64(byte)) &* 0x100000001b3
            b = (b ^ UInt64(byte)) &* 0x100000001b3 &+ a
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((a >> (UInt64(i) * 8)) & 0xff)
            bytes[i + 8] = UInt8((b >> (UInt64(i) * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50   // version 5 style
        bytes[8] = (bytes[8] & 0x3f) | 0x80   // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

#if os(iOS)
nonisolated struct WanderClockAlarmMetadata: AlarmMetadata {
    var alarmID: UUID
    var cityName: String
    var cityTime: String
}
#endif

/// Shows alarm notifications in the foreground and handles Snooze (Mac / Vision Pro).
nonisolated final class AlarmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let category = "WANDER_ALARM_CATEGORY"
    static let snoozeAction = "ACTION_SNOOZE"
    static let snoozePrefix = "snooze-"

    static func registerCategories() {
        let snooze = UNNotificationAction(identifier: snoozeAction, title: String(localized: "Snooze 9 min"), options: [])
        let category = UNNotificationCategory(identifier: Self.category, actions: [snooze], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.snoozeAction else { return }
        let request = UNNotificationRequest(
            identifier: "\(Self.snoozePrefix)\(UUID().uuidString)",
            content: response.notification.request.content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 9 * 60, repeats: false)
        )
        try? await center.add(request)
    }
}
