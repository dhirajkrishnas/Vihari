#if os(iOS)
import Foundation
import AlarmKit

public nonisolated struct WanderClockAlarmMetadata: AlarmMetadata, Sendable {
    public var alarmID: UUID
    public var cityName: String
    public var cityTime: String

    public init(alarmID: UUID, cityName: String, cityTime: String) {
        self.alarmID = alarmID
        self.cityName = cityName
        self.cityTime = cityTime
    }
}
#endif
