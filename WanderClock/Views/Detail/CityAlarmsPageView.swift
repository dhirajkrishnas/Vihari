import SwiftUI

struct CityAlarmsPageView: View {
    let city: PinnedCity
    let alarms: [CityAlarm]
    let onSetEnabled: (CityAlarm, Bool) -> Void
    let onDeleteAlarm: (CityAlarm) -> Void
    let onSaveAlarm: (CityAlarm) -> Void
    /// Closes the city and returns to the globe once onboarding's permission step is answered.
    var onFinishOnboarding: () -> Void = {}

    private enum Editor: Identifiable {
        case new
        case edit(CityAlarm)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let alarm): alarm.id.uuidString
            }
        }
    }

    @State private var editor: Editor?
    @State private var scheduler = AlarmScheduler.shared
    @State private var onboarding = OnboardingFlow.shared
    @State private var isRequestingPermission = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 14) {
                if onboarding.stage == .alarmPermission {
                    AlarmPermissionPrompt(
                        isRequesting: isRequestingPermission,
                        onAllow: allowAlarms,
                        onNotNow: onFinishOnboarding
                    )
                } else if scheduler.authorization == .denied {
                    PermissionBanner()
                }

                if alarms.isEmpty {
                    ContentUnavailableView {
                        Label("No Alarms", systemImage: "alarm")
                    } description: {
                        Text("Alarms here ring at \(city.name) time, wherever you are.")
                    } actions: {
                        Button("Add Alarm") { editor = .new }
                            .adaptiveGlassButtonStyle(prominent: onboarding.stage != .alarmPermission)
                    }
                    .padding(.vertical, 8)
                } else {
                    TimelineView(.everyMinute) { context in
                        VStack(spacing: 12) {
                            ForEach(alarms) { alarm in
                                AlarmItemRow(
                                    alarm: alarm,
                                    now: context.date,
                                    onSetEnabled: { onSetEnabled(alarm, $0) },
                                    onEdit: { editor = .edit(alarm) },
                                    onDelete: { withAnimation { onDeleteAlarm(alarm) } }
                                )
                                .transition(.opacity)
                            }
                        }
                    }

                    Button {
                        editor = .new
                    } label: {
                        Label("Add Alarm", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .adaptiveGlassButtonStyle(prominent: true)
                    .controlSize(.large)

                    Text("Alarms ring at \(city.name) time, wherever you are.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .animation(.smooth, value: alarms)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editor) { editor in
            switch editor {
            case .new:
                AddAlarmSheet(city: city, existing: nil, onSave: onSaveAlarm, onDelete: nil)
            case .edit(let alarm):
                AddAlarmSheet(city: city, existing: alarm, onSave: onSaveAlarm, onDelete: { onDeleteAlarm(alarm) })
            }
        }
    }

    private func allowAlarms() {
        isRequestingPermission = true
        Task {
            await scheduler.requestAuthorizationIfNeeded()
            isRequestingPermission = false
            onFinishOnboarding()
        }
    }
}

/// Onboarding's last step: asks for alarm permission in context, inside the first city.
private struct AlarmPermissionPrompt: View {
    let isRequesting: Bool
    let onAllow: () -> Void
    let onNotNow: () -> Void

    #if os(iOS)
    private static let message: LocalizedStringKey = "Allow WanderClock to ring alarms at the right moment, even when your device is locked or in Silent mode."
    #else
    private static let message: LocalizedStringKey = "Allow notifications so WanderClock can alert you at the right moment for each city."
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "alarm")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Let Alarms Ring")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(Self.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(action: onNotNow) {
                    Text("Not Now").frame(maxWidth: .infinity)
                }
                .adaptiveGlassButtonStyle()

                Button(action: onAllow) {
                    Group {
                        if isRequesting {
                            ProgressView()
                        } else {
                            Text("Allow Alarms")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .adaptiveGlassButtonStyle(prominent: true)
                .disabled(isRequesting)
            }
            .controlSize(.large)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 24)
    }
}
