import StoreKit
import SwiftUI

/// The Tip Jar: what tips are for, and one row per tip size.
struct DonationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = DonationStore.shared
    // The badges grow with Dynamic Type along with their symbols.
    @ScaledMetric(relativeTo: .title) private var headerBadgeSize: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var tierBadgeSize: CGFloat = 44

    var body: some View {
        SheetNavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerCard

                    if store.hasDonatedSuccessfully {
                        TipThanks()
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    tiersSection

                    footerNote
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .padding(20)
                .animation(.smooth, value: store.hasDonatedSuccessfully)
            }
            #if os(macOS)
            .macSheetHeader(Text("Tip Jar"))
            .macSheetFooter { MacSheetDoneButton() }
            #else
            .navigationTitle("Tip Jar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            #endif
            .background(SheetBackground())
            .sensoryFeedback(.success, trigger: store.hasDonatedSuccessfully)
            .tipErrorAlert(store)
            .task { await store.loadProducts() }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: headerBadgeSize, height: headerBadgeSize)
                .background(Color.accentColor.opacity(0.18), in: Circle())
                .accessibilityHidden(true)

            Text("Support WanderClock")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("WanderClock is independent, ad-free and respects your privacy. If it helps you stay connected across time zones, a tip directly supports ongoing development, new features, and design improvements.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .contentCard(cornerRadius: 24)
    }

    private var tiersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Choose an Amount", systemImage: "gift")

            VStack(spacing: 12) {
                ForEach(DonationTier.allCases) { tier in
                    HStack(spacing: 14) {
                        Image(systemName: tier.iconName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .frame(width: tierBadgeSize, height: tierBadgeSize)
                            .background(Color.accentColor.opacity(0.18), in: Circle())
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tier.title)
                                .font(.headline)
                            Text(tier.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        TipButton(tier: tier)
                    }
                    .padding(14)
                    .contentCard(cornerRadius: 20)
                }

                if store.loadFailed {
                    TipsUnavailableNote()
                }
            }
        }
    }

    private var footerNote: some View {
        VStack(spacing: 6) {
            Text("Tips are processed securely through your Apple Account and are completely optional.")
            Text("No features are locked behind tips.")
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

/// Buys one tip: tinted glass showing the App Store price, a spinner while it's bought, and a
/// placeholder until the price has loaded.
struct TipButton: View {
    let tier: DonationTier
    var showsIcon = false

    @Environment(\.purchase) private var purchase
    @State private var store = DonationStore.shared

    var body: some View {
        let price = store.displayPrice(for: tier)
        Button {
            Task { await store.purchase(tier, using: purchase) }
        } label: {
            ZStack {
                // Keeps the button's size while the spinner shows.
                label(price: price).opacity(store.purchasingTier == tier ? 0 : 1)
                if store.purchasingTier == tier {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 52)
        }
        .adaptiveGlassButtonStyle(prominent: true)
        .buttonBorderShape(.capsule)
        .disabled(price == nil || store.purchasingTier != nil)
        .accessibilityLabel(Text("\(tier.title), \(price ?? String(localized: "price loading"))"))
        .accessibilityHint(Text("Leaves a voluntary tip"))
    }

    private func label(price: String?) -> some View {
        HStack(spacing: 6) {
            if showsIcon {
                Image(systemName: tier.iconName)
            }
            Text(price ?? "$0.00")
                .monospacedDigit()
                .lineLimit(1)
                .redacted(reason: price == nil ? .placeholder : [])
        }
    }
}

/// Thanks after a tip goes through.
struct TipThanks: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Thank You!")
                    .font(.headline)
                Text("Your tip directly funds what comes next for WanderClock. Safe travels!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .contentCard(cornerRadius: 22, tint: .accentColor)
        .accessibilityElement(children: .combine)
    }
}

/// Shown when the App Store couldn't be reached, with a way to try again.
struct TipsUnavailableNote: View {
    @State private var store = DonationStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Text("Tips can’t load right now. Check your connection.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Try Again") { Task { await store.loadProducts() } }
                .font(.footnote.weight(.semibold))
                .adaptiveGlassButtonStyle()
                .disabled(store.isLoading)
        }
    }
}

extension View {
    /// Shows the tip store's error, if there is one.
    func tipErrorAlert(_ store: DonationStore) -> some View {
        alert("Couldn’t Complete Tip", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
