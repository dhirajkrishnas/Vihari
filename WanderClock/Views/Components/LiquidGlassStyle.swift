import SwiftUI

// WanderClock's material rules, following Apple's Liquid Glass guidance:
// • Glass is for the floating layer — bars, buttons, map tags and the cards/panels that float over the globe.
// • Content that sits ON glass (or scrolls in a list) uses quiet fills instead — never glass on glass.
// • Only primary actions get a tint.

extension View {
    /// Real Liquid Glass for floating surfaces over the globe.
    func floatingGlass(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        adaptiveGlass(in: .rect(cornerRadius: cornerRadius, style: .continuous), tint: tint?.opacity(0.22), interactive: interactive)
    }

    /// A quiet grouped surface for content inside glass panels, sheets and lists.
    func contentCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.10))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

/// Small uppercase section label, e.g. "HOURLY FORECAST".
struct SectionHeader: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .labelStyle(SectionHeaderLabelStyle())
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SectionHeaderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

/// Tinted capsule badge, e.g. "+9 HRS" or "Weekdays".
struct CapsuleBadge: View {
    let text: String
    var color: Color = .cyan

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
    }
}

/// A circular glass toolbar-style button for the floating bar over the globe.
struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 26, height: 26)
        }
        .adaptiveGlassButtonStyle()
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Platform adaptation
// visionOS has its own glass material (no Liquid Glass APIs), so these wrappers pick the native look per platform.

extension View {
    /// Liquid Glass on iOS/macOS; the system glass material on visionOS.
    @ViewBuilder
    func adaptiveGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if os(visionOS)
        glassBackgroundEffect(in: shape)
        #else
        glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        #endif
    }

    /// `.glass` / `.glassProminent` buttons, falling back to bordered styles on visionOS.
    @ViewBuilder
    func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
        #if os(visionOS)
        if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        #else
        if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        #endif
    }

    @ViewBuilder
    func dismissesKeyboardOnScroll() -> some View {
        #if os(visionOS)
        self
        #else
        scrollDismissesKeyboard(.interactively)
        #endif
    }
}

/// `GlassEffectContainer` where available, so neighbouring glass shapes blend and morph together.
struct AdaptiveGlassContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        #if os(visionOS)
        content
        #else
        GlassEffectContainer(spacing: spacing) { content }
        #endif
    }
}
