import SwiftUI

// WanderClock's material rules, following Apple's Liquid Glass guidance:
// • Glass is for the floating layer — bars, buttons, map tags and the cards/panels that float over the globe.
// • Content that sits ON glass (or scrolls in a list) uses quiet fills instead — never glass on glass.
// • Actions use tinted glass (the accent, tangerine) with white symbols; everything else uses plain
//   glass with white symbols. Symbols in buttons are never coloured.

extension Color {
    /// The app's accent, the tangerine of the clock hands in the app icon. It's also the
    /// AccentColor asset; this copy is for places outside the view hierarchy, such as AlarmKit.
    static let tangerine = Color(.sRGB, red: 1, green: 0.578, blue: 0)
}

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

/// The deep-space gradient behind every sheet.
struct SheetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.16), .black], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
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
    var color: Color = .accentColor

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

/// A circular glass button with a single symbol, for actions that float over content outside a
/// toolbar (toolbars give their buttons glass themselves). Prominent ones are tinted.
struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    var prominent = false
    let action: () -> Void

    /// Grows with Dynamic Type, so the glyph never outgrows its circle.
    @ScaledMetric(relativeTo: .body) private var glyphFrame: CGFloat = 26

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: glyphFrame, height: glyphFrame)
        }
        .adaptiveGlassButtonStyle(prominent: prominent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Related icon buttons sharing one capsule of glass, the way a toolbar groups its buttons. With
/// one button it's the same circle as a `GlassIconButton`, so the two sit together evenly.
struct GlassIconGroup<Content: View>: View {
    @ViewBuilder let content: Content

    /// Grows with Dynamic Type, like `GlassIconButton`'s.
    @ScaledMetric(relativeTo: .body) private var glyphFrame: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) { content }
            .buttonStyle(GroupedIconButtonStyle(glyphFrame: glyphFrame))
            .padding(.horizontal, 3)
            .foregroundStyle(.primary)
            .adaptiveGlass(in: Capsule(), interactive: true)
    }
}

/// One button in a `GlassIconGroup`: its icon, sized to match a `GlassIconButton`'s circle.
private struct GroupedIconButtonStyle: ButtonStyle {
    let glyphFrame: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .frame(width: glyphFrame, height: glyphFrame)
            // A large glass button pads its icon by 14.5 pt all round.
            .padding(.vertical, 14.5)
            .frame(width: glyphFrame + 23)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.55 : 1)
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

    /// Tinted glass (`.glassProminent`) for actions, plain glass for everything else, with white
    /// labels either way. visionOS has no Liquid Glass buttons, so it gets the bordered styles.
    @ViewBuilder
    func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
        #if os(visionOS)
        if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered).foregroundStyle(.primary) }
        #else
        if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass).foregroundStyle(.primary) }
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
