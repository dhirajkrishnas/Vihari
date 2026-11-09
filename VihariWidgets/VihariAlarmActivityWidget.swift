import ActivityKit
import WidgetKit
import SwiftUI
import AlarmKit
import AppIntents

extension Color {
    static let tangerine = Color(.sRGB, red: 1, green: 0.578, blue: 0)
}

struct StopAlarmWidgetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Alarm"
    static let description = IntentDescription("Stops the snoozed alarm.")
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
        }
        return .result()
    }
}

struct VihariAlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<VihariAlarmMetadata>.self) { context in
            AlarmCountdownLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.title2)
                        .foregroundStyle(Color.tangerine)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if case .countdown(let countdownState) = context.state.mode {
                        Text(timerInterval: countdownState.startDate...countdownState.fireDate, countsDown: true)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.tangerine)
                            .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.presentation.alert.title)
                                .font(.headline)
                                .lineLimit(1)
                            if let meta = context.attributes.metadata {
                                Text("\(meta.cityTime) · \(meta.cityName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button(role: .cancel, intent: StopAlarmWidgetIntent(alarmID: context.state.alarmID)) {
                            Label("Stop", systemImage: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop Alarm")
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(Color.tangerine)
            } compactTrailing: {
                if case .countdown(let countdownState) = context.state.mode {
                    Text(timerInterval: countdownState.startDate...countdownState.fireDate, countsDown: true)
                        .monospacedDigit()
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.tangerine)
                        .frame(width: 44)
                }
            } minimal: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(Color.tangerine)
            }
            .keylineTint(Color.tangerine)
        }
    }
}

struct AlarmCountdownLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<VihariAlarmMetadata>>

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.tangerine.opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: "moon.zzz.fill")
                    .font(.title3)
                    .foregroundStyle(Color.tangerine)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(context.attributes.presentation.alert.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("· Snoozing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let meta = context.attributes.metadata {
                    Text("\(meta.cityTime) · \(meta.cityName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case .countdown(let countdownState) = context.state.mode {
                    HStack(spacing: 4) {
                        Text("Rings in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(timerInterval: countdownState.startDate...countdownState.fireDate, countsDown: true)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.tangerine)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            Button(role: .cancel, intent: StopAlarmWidgetIntent(alarmID: context.state.alarmID)) {
                Text("Stop")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop Alarm")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .activityBackgroundTint(Color(red: 0.05, green: 0.08, blue: 0.16))
    }
}
