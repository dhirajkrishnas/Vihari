import SwiftUI

/// First-run introduction, shown over the live globe. The last page asks for a first city.
struct OnboardingView: View {
    /// True when cities already exist (for example, synced from another device).
    let hasCities: Bool
    let onChooseCity: () -> Void
    let onContinueWithExistingCities: () -> Void

    @State private var page = 0
    @State private var direction: Edge = .trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 44

    private struct Page {
        let symbol: String
        let title: LocalizedStringKey
        let message: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(symbol: "globe",
             title: "The World at a Glance",
             message: "Pin the cities you care about and see their local time on a living globe."),
        Page(symbol: "cloud.sun",
             title: "Weather Where They Are",
             message: "Current conditions, plus hourly and 10‑day forecasts for every city."),
        Page(symbol: "alarm",
             title: "Alarms on Their Time",
             message: "Set an alarm in a city’s local time. It rings at the right moment wherever you are, even when the clocks change."),
        Page(symbol: "mappin.and.ellipse",
             title: "Pin Your First City",
             message: "Choose a city to get started. You can add more at any time.")
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    /// The last page doesn't ask for a first city when there already are some.
    private var currentPage: Page {
        guard isLastPage, hasCities else { return pages[page] }
        return Page(symbol: "mappin.and.ellipse",
                    title: "Welcome Back",
                    message: "Your pinned cities are ready. You can add more at any time.")
    }

    var body: some View {
        VStack {
            Spacer()

            panel
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .animation(.smooth, value: page)
        .toolbar {
            if !isLastPage {
                ToolbarItem(placement: .primaryAction) {
                    Button("Skip") { go(to: pages.count - 1) }
                }
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 24) {
            // At the largest text sizes the page scrolls rather than pushing the button off screen.
            ViewThatFits(in: .vertical) {
                pageContent(currentPage)
                ScrollView { pageContent(currentPage) }
                    .scrollBounceBehavior(.basedOnSize)
            }
                .id(page)
                .transition(reduceMotion ? .opacity : .push(from: direction))
                .frame(maxWidth: .infinity, minHeight: 210, alignment: .top)
                .clipped()

            pageIndicator

            Button {
                if !isLastPage {
                    go(to: page + 1)
                } else if hasCities {
                    onContinueWithExistingCities()
                } else {
                    onChooseCity()
                }
            } label: {
                Text(isLastPage ? (hasCities ? "Continue" : "Choose a City") : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .adaptiveGlassButtonStyle(prominent: true)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .floatingGlass(cornerRadius: 36)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    // Swiping toward the leading edge moves on, in either reading direction.
                    let forward = layoutDirection == .rightToLeft ? value.translation.width : -value.translation.width
                    if forward > 40, !isLastPage {
                        go(to: page + 1)
                    } else if forward < -40, page > 0 {
                        go(to: page - 1)
                    }
                }
        )
        .accessibilityScrollAction { edge in
            switch edge {
            case .trailing where !isLastPage: go(to: page + 1)
            case .leading where page > 0: go(to: page - 1)
            default: break
            }
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    private func pageContent(_ item: Page) -> some View {
        VStack(spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: symbolSize, weight: .regular))
                .foregroundStyle(.tint)
                .frame(minHeight: symbolSize * 1.27)
                .accessibilityHidden(true)
            Text(item.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(item.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: index == page ? 18 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Page"))
        .accessibilityValue(Text("\(page + 1) of \(pages.count)"))
        .accessibilityAdjustableAction { change in
            switch change {
            case .increment where !isLastPage: go(to: page + 1)
            case .decrement where page > 0: go(to: page - 1)
            default: break
            }
        }
    }

    private func go(to newPage: Int) {
        direction = newPage > page ? .trailing : .leading
        page = newPage
    }
}
