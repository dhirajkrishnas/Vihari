import Foundation
import Network
import Observation

/// Whether the device is online, and whether the person has asked to save data (Low Data Mode).
@Observable
final class NetworkStatus {
    static let shared = NetworkStatus()

    private(set) var isOnline = true
    /// Low Data Mode is on, so optional downloads (like prefetching globe imagery) wait.
    private(set) var isConstrained = false

    /// Called each time the device comes back online.
    @ObservationIgnored var onReconnect: (() -> Void)?

    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let constrained = path.isConstrained
            Task { @MainActor in self?.update(online: online, constrained: constrained) }
        }
        monitor.start(queue: DispatchQueue(label: "WanderClock.NetworkStatus", qos: .utility))
    }

    private func update(online: Bool, constrained: Bool) {
        let reconnected = online && !isOnline
        isOnline = online
        isConstrained = constrained
        if reconnected { onReconnect?() }
    }
}
