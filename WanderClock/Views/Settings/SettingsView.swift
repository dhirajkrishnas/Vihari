import SwiftUI

struct SettingsView: View {
    @Bindable var store: CityStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable private var settings = AppSettings.shared
    @State private var confirmingDeleteAll = false

    private var isSignedInToICloud: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    unitsSection
                    syncSection
                    aboutSection
                    dataSection
                    footer
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .background(SheetBackground())
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onChange(of: settings.isICloudSyncEnabled) { _, enabled in
                if enabled { Task { await store.syncNow() } }
            }
            .confirmationDialog("Delete All Data?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete All Data", role: .destructive) {
                    store.deleteAllData()
                    dismiss()
                }
            } message: {
                if settings.isICloudSyncEnabled {
                    Text("All your cities, alarms and preferences will be removed from this device and from your other devices that use iCloud Sync. This can’t be undone.")
                } else {
                    Text("All your cities, alarms and preferences will be removed from this device. This can’t be undone.")
                }
            }
        }
    }

    // MARK: Units

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Units & Formats", systemImage: "ruler")

            VStack(spacing: 12) {
                row("Temperature", systemImage: "thermometer.medium") {
                    Picker("Temperature", selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 130)
                }
                divider
                row("Time Format", systemImage: "clock") {
                    Picker("Time Format", selection: $settings.timeFormat) {
                        ForEach(AppTimeFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                divider
                row("Wind Speed", systemImage: "wind") {
                    Picker("Wind Speed", selection: $settings.windSpeedUnit) {
                        ForEach(WindSpeedUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                divider
                row("Distance", systemImage: "eye") {
                    Picker("Distance", selection: $settings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                divider
                row("Pressure", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                    Picker("Pressure", selection: $settings.pressureUnit) {
                        ForEach(PressureUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(18)
            .contentCard(cornerRadius: 22)
        }
    }

    // MARK: iCloud

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "iCloud Sync", systemImage: "icloud.fill")

            VStack(spacing: 14) {
                Toggle(isOn: $settings.isICloudSyncEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sync with iCloud")
                            .font(.headline)
                        Text("Keep pinned cities, alarms and preferences the same on your iPhone, iPad, Mac and Apple Vision Pro.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if settings.isICloudSyncEnabled {
                    divider
                    adaptiveStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label {
                                Text(isSignedInToICloud ? "iCloud Active" : "Not Signed In to iCloud")
                            } icon: {
                                Circle()
                                    .fill(isSignedInToICloud ? Color.green : .orange)
                                    .frame(width: 8, height: 8)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSignedInToICloud ? Color.green : .orange)

                            if isSignedInToICloud, let lastDate = settings.lastSyncDate {
                                TimelineView(.everyMinute) { context in
                                    Group {
                                        if context.date.timeIntervalSince(lastDate) < 60 {
                                            Text("Last synced just now")
                                        } else {
                                            Text("Last synced \(lastDate.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(.autoupdatingCurrent)))")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        Button {
                            Task { await store.syncNow() }
                        } label: {
                            if store.isSyncing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .disabled(store.isSyncing || !isSignedInToICloud)
                    }
                    .transition(.opacity)
                }
            }
            .padding(18)
            .contentCard(cornerRadius: 22, tint: settings.isICloudSyncEnabled ? .cyan : nil)
            .animation(.snappy, value: settings.isICloudSyncEnabled)
        }
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "About", systemImage: "info.circle")

            VStack(spacing: 0) {
                pageLink("Privacy Policy", systemImage: "hand.raised") { PrivacyPolicyView() }
                divider
                pageLink("Terms of Use", systemImage: "doc.text") { TermsOfUseView() }
                divider
                pageLink("Acknowledgements", systemImage: "heart.text.square") { AcknowledgementsView() }
            }
            .padding(.horizontal, 18)
            .contentCard(cornerRadius: 22)
        }
    }

    // MARK: Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) {
                confirmingDeleteAll = true
            } label: {
                Label("Delete All Data", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .contentCard(cornerRadius: 22)

            Text("Removes every city, alarm and preference WanderClock has stored.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("WanderClock")
                .font(.headline.weight(.bold))
            Text("Version \(appVersion)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("World time, weather and travel-proof alarms for the cities you care about.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Helpers

    private var divider: some View {
        Divider().overlay(.white.opacity(0.1))
    }

    /// Side by side normally; stacked at the accessibility text sizes so nothing truncates.
    private func adaptiveStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout())
        return layout { content() }
    }

    private func row<Control: View>(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder control: () -> Control) -> some View {
        adaptiveStack {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            control()
                // The row's label already names the setting (a Mac picker would repeat it).
                .labelsHidden()
        }
    }

    private func pageLink<Destination: View>(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
