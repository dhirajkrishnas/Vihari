import Foundation
import Observation
import SwiftUI
import os

/// The single source of truth for pinned cities, alarms and weather. Both the UI and
/// App Intents (Siri / Shortcuts) go through `CityStore.shared`, so they never disagree.
@Observable
final class CityStore {
    static let shared = CityStore()

    private(set) var cities: [PinnedCity] = []
    private(set) var alarms: [CityAlarm] = []
    private(set) var weatherStates: [UUID: WeatherState] = [:]
    private(set) var isSyncing = false
    var selectedCityID: UUID?

    var selectedCity: PinnedCity? {
        get { selectedCityID.flatMap { id in cities.first { $0.id == id } } }
        set { selectedCityID = newValue?.id }
    }

    @ObservationIgnored private var citiesModifiedAt: Date = .distantPast
    @ObservationIgnored private var alarmsModifiedAt: Date = .distantPast
    /// When each unpinned city and deleted alarm was removed, so the removal reaches other devices.
    @ObservationIgnored private var cityRemovals: [String: Date] = [:]
    @ObservationIgnored private var alarmRemovals: [String: Date] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var weatherRefreshTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.dhirajkrishnasimhadri.WanderClock", category: "Store")
    private let cloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let cities = "WanderClock_Cities_v2"
        static let alarms = "WanderClock_Alarms_v2"
        static let legacyCities = "WanderClock_PinnedCities_v1"
        static let legacyAlarms = "WanderClock_Alarms_v1"
    }

    private init() {
        loadPersistedData()
        observeSystemChanges()
        AlarmScheduler.shared.onSystemAlarmsChanged = { [weak self] in
            self?.alarmsDidFireOrChange()
        }
        NetworkStatus.shared.onReconnect = { [weak self] in
            self?.refreshWeather(staleAfter: 15 * 60)
        }
        Task { await restoreSavedWeather() }
    }

    // MARK: - Lifecycle

    /// Call when the app becomes active: syncs, refreshes stale weather, retires finished
    /// one-time alarms and tops up the queue of scheduled alarm rings.
    func appDidBecomeActive() {
        if AppSettings.shared.isICloudSyncEnabled {
            cloud.synchronize()
            syncWithCloud()
        }
        alarmsDidFireOrChange()
        refreshWeather(staleAfter: 15 * 60)
    }

    /// Retires one-time alarms that have rung and queues upcoming rings, finishing once the
    /// system schedule is up to date. Used when an alarm is stopped and by background refresh,
    /// when the app may be suspended again right after.
    func refreshAlarmSchedule() async {
        if AppSettings.shared.isICloudSyncEnabled { syncWithCloud() }
        alarmsDidFireOrChange()
        await AlarmScheduler.shared.waitUntilIdle()
    }

    // MARK: - Cities

    @discardableResult
    func addCity(_ city: PinnedCity) -> Bool {
        guard !cities.contains(where: { $0.isSamePlace(as: city) }) else { return false }
        cities.append(city)
        cityRemovals[city.id.uuidString] = nil
        citiesDidChange()
        loadWeather(for: city, force: true)
        return true
    }

    func removeCity(_ city: PinnedCity) {
        let now = Date.now
        if selectedCityID == city.id { selectedCityID = nil }
        cities.removeAll { $0.id == city.id }
        cityRemovals[city.id.uuidString] = now
        weatherStates[city.id] = nil
        let removedAlarms = alarms.filter { $0.cityId == city.id }
        alarms.removeAll { $0.cityId == city.id }
        for alarm in removedAlarms { alarmRemovals[alarm.id.uuidString] = now }
        citiesDidChange()
        if !removedAlarms.isEmpty { alarmsDidChange() }
    }

    func moveCities(from source: IndexSet, to destination: Int) {
        cities.move(fromOffsets: source, toOffset: destination)
        citiesDidChange()
    }

    // MARK: - Alarms

    func alarms(for city: PinnedCity) -> [CityAlarm] {
        alarms.filter { $0.cityId == city.id }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    func addAlarm(_ alarm: CityAlarm) {
        alarms.append(alarm.isEnabled ? alarm.armed() : alarm)
        alarmRemovals[alarm.id.uuidString] = nil
        alarmsDidChange(requestPermission: alarm.isEnabled)
    }

    func updateAlarm(_ alarm: CityAlarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        var updated = alarm.isEnabled ? alarm.armed() : alarm
        updated.modifiedAt = .now
        alarms[index] = updated
        alarmsDidChange(requestPermission: updated.isEnabled)
    }

    /// Saves an alarm from the editor: updates it if it exists, otherwise adds it.
    func saveAlarm(_ alarm: CityAlarm) {
        if alarms.contains(where: { $0.id == alarm.id }) {
            updateAlarm(alarm)
        } else {
            addAlarm(alarm)
        }
    }

    func setAlarm(_ alarm: CityAlarm, enabled: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        if enabled {
            alarms[index] = alarms[index].armed()
        } else {
            alarms[index].isEnabled = false
            alarms[index].modifiedAt = .now
        }
        alarmsDidChange(requestPermission: enabled)
    }

    func toggleAlarm(_ alarm: CityAlarm) {
        setAlarm(alarm, enabled: !alarm.isEnabled)
    }

    func deleteAlarm(_ alarm: CityAlarm) {
        alarms.removeAll { $0.id == alarm.id }
        alarmRemovals[alarm.id.uuidString] = .now
        alarmsDidChange()
    }

    /// Switches off one-time alarms that have rung, then re-syncs the system schedule.
    private func alarmsDidFireOrChange() {
        let now = Date.now
        var changed = false
        for index in alarms.indices where alarms[index].hasExpired(at: now) {
            alarms[index].isEnabled = false
            alarms[index].modifiedAt = now
            changed = true
        }
        // Older one-time alarms saved before fire dates existed: arm them so they can expire.
        for index in alarms.indices where alarms[index].isEnabled && !alarms[index].repeatSchedule.repeats && alarms[index].oneTimeFireDate == nil {
            alarms[index] = alarms[index].armed(from: alarms[index].modifiedAt)
            changed = true
        }
        if changed {
            alarmsDidChange()
        } else {
            AlarmScheduler.shared.reconcile(with: schedulableAlarms, requestPermission: false)
        }
    }

    // MARK: - Weather

    func weatherState(for city: PinnedCity) -> WeatherState {
        weatherStates[city.id] ?? .loading
    }

    func weather(for city: PinnedCity) -> WeatherReport? {
        weatherStates[city.id]?.report
    }

    func refreshWeather(staleAfter maxAge: TimeInterval = 0) {
        weatherRefreshTask?.cancel()
        let now = Date.now
        let targets = cities.filter { city in
            guard let report = weatherStates[city.id]?.report else { return true }
            return now.timeIntervalSince(report.lastUpdated) >= maxAge
        }
        guard !targets.isEmpty else { return }
        weatherRefreshTask = Task {
            await withTaskGroup(of: (UUID, WeatherReport?).self) { group in
                for city in targets {
                    group.addTask {
                        (city.id, try? await WeatherServiceManager.shared.fetchWeather(for: city))
                    }
                }
                for await (id, report) in group {
                    // A newer refresh has taken over; it reports for these cities itself.
                    guard !Task.isCancelled else { return }
                    record(report, for: id)
                }
            }
        }
    }

    func loadWeather(for city: PinnedCity, force: Bool = false) {
        if !force, weatherStates[city.id]?.report != nil { return }
        if weatherStates[city.id]?.report == nil { weatherStates[city.id] = .loading }
        Task {
            let report = try? await WeatherServiceManager.shared.fetchWeather(for: city, forceRefresh: force)
            record(report, for: city.id)
        }
    }

    /// Shows a new report; without one, keeps any older report rather than replacing it with an error.
    private func record(_ report: WeatherReport?, for id: UUID) {
        guard cities.contains(where: { $0.id == id }) else { return }
        if let report {
            weatherStates[id] = .loaded(report)
        } else if weatherStates[id]?.report == nil {
            weatherStates[id] = .unavailable
        }
    }

    /// Shows the weather saved last time while fresh weather loads.
    private func restoreSavedWeather() async {
        let saved = await WeatherServiceManager.shared.savedReports()
        for city in cities where weatherStates[city.id]?.report == nil {
            if let report = saved[city.id] { weatherStates[city.id] = .loaded(report) }
        }
    }

    // MARK: - Delete All Data

    /// Removes every city, alarm and saved forecast and resets preferences. With iCloud Sync
    /// on, the removal reaches your other devices too.
    func deleteAllData() {
        let now = Date.now
        let syncing = AppSettings.shared.isICloudSyncEnabled
        weatherRefreshTask?.cancel()
        selectedCityID = nil
        if syncing {
            for city in cities { cityRemovals[city.id.uuidString] = now }
            for alarm in alarms { alarmRemovals[alarm.id.uuidString] = now }
        } else {
            cityRemovals = [:]
            alarmRemovals = [:]
        }
        cities = []
        alarms = []
        weatherStates = [:]
        citiesModifiedAt = now
        alarmsModifiedAt = now
        defaults.removeObject(forKey: Keys.legacyCities)
        defaults.removeObject(forKey: Keys.legacyAlarms)
        save(citiesSnapshot, key: Keys.cities)
        save(alarmsSnapshot, key: Keys.alarms)
        if syncing { syncWithCloud() }
        AlarmScheduler.shared.reconcile(with: [], requestPermission: false)
        Task { await WeatherServiceManager.shared.removeAllReports() }
        GlobeImageryPrewarmer.shared.reset()
        AppSettings.shared.resetPreferences()
        OnboardingFlow.shared.restart()
    }

    // MARK: - Persistence & iCloud

    /// One collection as it's saved, on this device and in iCloud.
    private struct Snapshot<Item: Codable & Hashable>: Codable, Hashable {
        var items: [Item]
        var modifiedAt: Date
        /// When each removed item was removed, keyed by its ID. A removal beats any older copy
        /// of the item from another device. Kept for 90 days.
        var removals: [String: Date]

        init(items: [Item], modifiedAt: Date, removals: [String: Date]) {
            self.items = items
            self.modifiedAt = modifiedAt
            self.removals = removals
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // One item that can't be read (say, from a newer version) mustn't lose the rest.
            items = try c.decode([Lossy<Item>].self, forKey: .items).compactMap(\.value)
            modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
            removals = (try? c.decodeIfPresent([String: Date].self, forKey: .removals)) ?? [:]
        }

        func hasSameContent(as other: Snapshot?) -> Bool {
            guard let other else { return false }
            return items == other.items && removals == other.removals
        }
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    private var citiesSnapshot: Snapshot<PinnedCity> {
        Snapshot(items: cities, modifiedAt: citiesModifiedAt, removals: cityRemovals)
    }

    private var alarmsSnapshot: Snapshot<CityAlarm> {
        Snapshot(items: alarms, modifiedAt: alarmsModifiedAt, removals: alarmRemovals)
    }

    /// Only alarms whose city is still pinned may ring; an alarm the user can't see must never fire.
    private var schedulableAlarms: [CityAlarm] {
        let cityIDs = Set(cities.map(\.id))
        return alarms.filter { cityIDs.contains($0.cityId) }
    }

    private func loadPersistedData() {
        if let snapshot = readLocal(PinnedCity.self, key: Keys.cities, legacyKey: Keys.legacyCities) {
            cities = snapshot.items
            citiesModifiedAt = snapshot.modifiedAt
            cityRemovals = Self.pruned(snapshot.removals)
        }
        if let snapshot = readLocal(CityAlarm.self, key: Keys.alarms, legacyKey: Keys.legacyAlarms) {
            alarms = snapshot.items
            alarmsModifiedAt = snapshot.modifiedAt
            alarmRemovals = Self.pruned(snapshot.removals)
        }
        if AppSettings.shared.isICloudSyncEnabled {
            cloud.synchronize()
            syncWithCloud()
        }
    }

    private func readLocal<Item: Codable & Hashable>(_: Item.Type, key: String, legacyKey: String) -> Snapshot<Item>? {
        if let data = defaults.data(forKey: key),
           let snapshot = try? JSONDecoder().decode(Snapshot<Item>.self, from: data) {
            return snapshot
        }
        // Migrate the original v1 format (a bare array).
        if let data = defaults.data(forKey: legacyKey),
           let items = try? JSONDecoder().decode([Item].self, from: data) {
            return Snapshot(items: items, modifiedAt: .distantPast, removals: [:])
        }
        return nil
    }

    private func save<Item: Codable & Hashable>(_ snapshot: Snapshot<Item>, key: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    private func citiesDidChange() {
        citiesModifiedAt = .now
        save(citiesSnapshot, key: Keys.cities)
        Task { [ids = Set(cities.map(\.id))] in await WeatherServiceManager.shared.keepReports(for: ids) }
        if AppSettings.shared.isICloudSyncEnabled { syncWithCloud() }
    }

    private func alarmsDidChange(requestPermission: Bool = false) {
        alarmsModifiedAt = .now
        save(alarmsSnapshot, key: Keys.alarms)
        if AppSettings.shared.isICloudSyncEnabled { syncWithCloud() }
        AlarmScheduler.shared.reconcile(with: schedulableAlarms, requestPermission: requestPermission)
    }

    /// Merges this device's cities and alarms with iCloud's copy, keeps the result here, and
    /// sends it back if iCloud was missing anything.
    ///
    /// Nothing is lost when two devices change things around the same time: each city or
    /// alarm keeps its newest version, a removal wins over any older copy, and the order comes
    /// from whichever device changed the list last. Turning sync on for the first time combines
    /// both sides rather than replacing one with the other.
    private func syncWithCloud() {
        guard AppSettings.shared.isICloudSyncEnabled else { return }
        let remoteCities = cloudSnapshot(PinnedCity.self, key: Keys.cities)
        let remoteAlarms = cloudSnapshot(CityAlarm.self, key: Keys.alarms)

        var mergedCities = remoteCities.map { Self.merge(citiesSnapshot, $0, version: \.dateAdded) } ?? citiesSnapshot
        let (uniqueCities, replacedCities) = Self.removingDuplicatePlaces(mergedCities.items)
        mergedCities.items = uniqueCities

        var mergedAlarms = remoteAlarms.map { Self.merge(alarmsSnapshot, $0, version: \.modifiedAt) } ?? alarmsSnapshot
        var keptAlarms: [CityAlarm] = []
        for var alarm in mergedAlarms.items {
            if let replacement = replacedCities[alarm.cityId] { alarm.cityId = replacement }
            // An alarm whose city was unpinned on another device goes with it.
            if let removedAt = mergedCities.removals[alarm.cityId.uuidString] {
                mergedAlarms.removals[alarm.id.uuidString] = max(removedAt, alarm.modifiedAt)
                continue
            }
            keptAlarms.append(alarm)
        }
        mergedAlarms.items = keptAlarms

        let citiesChanged = mergedCities != citiesSnapshot
        let alarmsChanged = mergedAlarms != alarmsSnapshot
        if citiesChanged {
            adopt(mergedCities)
            save(mergedCities, key: Keys.cities)
        }
        if alarmsChanged {
            alarms = mergedAlarms.items
            alarmsModifiedAt = mergedAlarms.modifiedAt
            alarmRemovals = mergedAlarms.removals
            save(mergedAlarms, key: Keys.alarms)
        }
        if !mergedCities.hasSameContent(as: remoteCities) { upload(mergedCities, key: Keys.cities) }
        if !mergedAlarms.hasSameContent(as: remoteAlarms) { upload(mergedAlarms, key: Keys.alarms) }
        if citiesChanged || alarmsChanged {
            AlarmScheduler.shared.reconcile(with: schedulableAlarms, requestPermission: false)
        }
        AppSettings.shared.markSynced()
    }

    private func adopt(_ snapshot: Snapshot<PinnedCity>) {
        let known = Set(cities.map(\.id))
        cities = snapshot.items
        citiesModifiedAt = snapshot.modifiedAt
        cityRemovals = snapshot.removals
        let current = Set(cities.map(\.id))
        for city in cities where !known.contains(city.id) { loadWeather(for: city) }
        for id in weatherStates.keys where !current.contains(id) { weatherStates[id] = nil }
        if let selected = selectedCityID, !current.contains(selected) { selectedCityID = nil }
    }

    private func cloudSnapshot<Item: Codable & Hashable>(_: Item.Type, key: String) -> Snapshot<Item>? {
        guard let data = cloud.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot<Item>.self, from: data)
    }

    private func upload<Item: Codable & Hashable>(_ snapshot: Snapshot<Item>, key: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        cloud.set(data, forKey: key)
    }

    /// Combines two copies of a collection: the newest version of every item, minus items
    /// removed after their last change, in the order of whichever copy changed last.
    private static func merge<Item: Identifiable & Codable & Hashable>(
        _ local: Snapshot<Item>, _ remote: Snapshot<Item>, version: (Item) -> Date
    ) -> Snapshot<Item> where Item.ID == UUID {
        var removals = local.removals.merging(remote.removals) { max($0, $1) }
        var newest: [UUID: Item] = [:]
        for item in local.items + remote.items {
            if let kept = newest[item.id], version(kept) >= version(item) { continue }
            newest[item.id] = item
        }
        for (id, item) in newest {
            guard let removedAt = removals[id.uuidString] else { continue }
            if removedAt >= version(item) {
                newest[id] = nil
            } else {
                // Changed again after it was removed elsewhere, so it stays.
                removals[id.uuidString] = nil
            }
        }
        let (first, second) = local.modifiedAt >= remote.modifiedAt ? (local, remote) : (remote, local)
        var seen = Set<UUID>()
        let items = (first.items + second.items).compactMap { item -> Item? in
            guard seen.insert(item.id).inserted else { return nil }
            return newest[item.id]
        }
        return Snapshot(items: items, modifiedAt: max(local.modifiedAt, remote.modifiedAt), removals: pruned(removals))
    }

    /// Two devices may each have pinned the same place before they first synced. The earlier
    /// pin is kept (the same choice on every device), and the other's alarms move to it.
    private static func removingDuplicatePlaces(_ cities: [PinnedCity]) -> (cities: [PinnedCity], replaced: [UUID: UUID]) {
        let ranked = cities.sorted { ($0.dateAdded, $0.id.uuidString) < ($1.dateAdded, $1.id.uuidString) }
        var keepers: [PinnedCity] = []
        var replaced: [UUID: UUID] = [:]
        for city in ranked {
            if let keeper = keepers.first(where: { $0.isSamePlace(as: city) }) {
                replaced[city.id] = keeper.id
            } else {
                keepers.append(city)
            }
        }
        guard !replaced.isEmpty else { return (cities, [:]) }
        return (cities.filter { replaced[$0.id] == nil }, replaced)
    }

    private static func pruned(_ removals: [String: Date]) -> [String: Date] {
        let cutoff = Date.now.addingTimeInterval(-90 * 86_400)
        return removals.filter { $0.value > cutoff }
    }

    /// Sync Now: pulls the latest from iCloud and sends anything this device has that iCloud doesn't.
    func syncNow() async {
        guard AppSettings.shared.isICloudSyncEnabled else { return }
        isSyncing = true
        defer { isSyncing = false }
        cloud.synchronize()
        AppSettings.shared.applyCloudSettings()
        syncWithCloud()
        cloud.synchronize()
        try? await Task.sleep(for: .milliseconds(400))
    }

    private func observeSystemChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated {
                guard let self, AppSettings.shared.isICloudSyncEnabled else { return }
                if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                    self.log.error("iCloud key-value storage is full")
                    return
                }
                self.log.info("Received iCloud change")
                AppSettings.shared.applyCloudSettings()
                self.syncWithCloud()
            }
        })
        // Alarms are stored as absolute moments, so travel needs no rescheduling,
        // but a manual clock change can make one-time alarms expire.
        observers.append(center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.alarmsDidFireOrChange() }
        })
    }
}

extension PinnedCity {
    /// Two pins are the same place if they're within ~5 km of each other.
    nonisolated func isSamePlace(as other: PinnedCity) -> Bool {
        if id == other.id { return true }
        return abs(latitude - other.latitude) < 0.05 && abs(longitude - other.longitude) < 0.05
    }
}
