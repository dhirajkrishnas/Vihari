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
                    .adaptiveGlassButtonStyle()
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

struct AlarmItemRow: View {
    let alarm: CityAlarm
    let now: Date
    let onSetEnabled: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var confirmingDelete = false
    /// The large alarm time follows Dynamic Type like the rest of the text.
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(alarm.formattedCityTime)
                        .font(.system(size: timeSize, weight: .light))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(alarm.label), \(alarm.repeatSchedule.title)")
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .foregroundStyle(alarm.isEnabled ? .primary : .secondary)
                Spacer()
                Toggle(isOn: Binding(get: { alarm.isEnabled }, set: { onSetEnabled($0) })) {
                    Text(alarm.label)
                }
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: alarm.isEnabled)
            }

            Divider()

            Label {
                Text(alarm.travelerContextSummary(from: now))
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "location")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .contentCard(cornerRadius: 22)
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture(perform: onEdit)
        // VoiceOver hears one switch per alarm, like the Clock app, with Edit and Delete as actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(alarm.formattedCityTime) \(alarm.cityName) time, \(alarm.label), \(alarm.repeatSchedule.title)"))
        .accessibilityValue(alarm.isEnabled ? Text("On. \(alarm.travelerContextSummary(from: now))") : Text("Off"))
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { onSetEnabled(!alarm.isEnabled) }
        .accessibilityAction(named: Text("Edit"), onEdit)
        .accessibilityAction(named: Text("Delete")) { confirmingDelete = true }
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Delete “\(alarm.label)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Alarm", role: .destructive, action: onDelete)
        }
    }
}

/// Shown when the user has turned off alarm permission for WanderClock.
private struct PermissionBanner: View {
    @Environment(\.openURL) private var openURL

    #if os(macOS)
    private static let message: LocalizedStringKey = "Allow WanderClock notifications in System Settings so alarms can alert you."
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")
    #else
    private static let message: LocalizedStringKey = "Allow WanderClock to schedule alarms in Settings so they can ring."
    private static let settingsURL = URL(string: UIApplication.openSettingsURLString)
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Alarms Are Turned Off")
                    .font(.subheadline.weight(.semibold))
                Text(Self.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = Self.settingsURL {
                    Button("Open Settings") { openURL(url) }
                        .font(.footnote.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .contentCard(cornerRadius: 20, tint: .orange)
    }
}
