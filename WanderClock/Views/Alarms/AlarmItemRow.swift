import SwiftUI

/// One alarm: its time in the city, label and schedule, when that is for the person, and an on/off
/// switch. Tap to edit; Edit and Delete are also in its context menu.
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
                    Text("\(alarm.label), \(alarm.scheduleSummary(now: now))")
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .foregroundStyle(alarm.isEnabled ? .primary : .secondary)
                Spacer()
                Toggle(isOn: Binding(get: { alarm.isEnabled }, set: { onSetEnabled($0) })) {
                    Text(alarm.label)
                }
                .labelsHidden()
                .toggleStyle(.switch)
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
        .accessibilityLabel(Text("\(alarm.formattedCityTime) \(alarm.cityName) time, \(alarm.label), \(alarm.scheduleSummary(now: now))"))
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
struct PermissionBanner: View {
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
                        .adaptiveGlassButtonStyle()
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .contentCard(cornerRadius: 20, tint: .orange)
    }
}
