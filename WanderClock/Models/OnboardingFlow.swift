import Foundation
import Observation

/// First-run flow: intro pages → pin a first city → allow alarms in that city's detail → back to the globe.
@Observable
final class OnboardingFlow {
    static let shared = OnboardingFlow()

    enum Stage {
        /// The intro pages, ending with picking a first city.
        case intro
        /// The new city's detail is open on its Alarms page, asking for alarm permission.
        case alarmPermission
        case finished
    }

    private(set) var stage: Stage

    private static let completedKey = "WanderClock_OnboardingCompleted"

    private init() {
        stage = UserDefaults.standard.bool(forKey: Self.completedKey) ? .finished : .intro
    }

    func didPinFirstCity() {
        stage = .alarmPermission
    }

    func finish() {
        stage = .finished
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }

    /// Starts over from the intro (after Delete All Data).
    func restart() {
        stage = .intro
        UserDefaults.standard.set(false, forKey: Self.completedKey)
    }
}
