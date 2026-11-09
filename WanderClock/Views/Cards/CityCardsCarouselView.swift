import SwiftUI

struct CityCardsCarouselView: View {
    /// Space between the cards, and between the cards and the screen's side and bottom edges.
    static let edgeInset: CGFloat = 12

    let cities: [PinnedCity]
    /// Which card leads the row. The owner keeps it, so when a city's panel closes and the row
    /// is rebuilt, it comes back where it was instead of jumping to the first card.
    @Binding var position: ScrollPosition
    let weatherProvider: (PinnedCity) -> WeatherState
    let alarmsProvider: (PinnedCity) -> [CityAlarm]
    let onSelectCity: (PinnedCity) -> Void
    let onUnpinCity: (PinnedCity) -> Void
    let onAddCityTap: () -> Void
    /// True while a city's sheet is up. The cards fade away meanwhile, so they don't show beside
    /// the sheet or through its glass.
    var isUnderSheet = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Every card's corner radius. It's measured where the first card rests, so the row's corners
    /// follow the screen's curve, and then it stays fixed: a shape that tracked the screen's
    /// corners would round differently at every scroll position.
    @State private var cornerRadius = LiquidGlassCityCard.minimumCornerRadius

    var body: some View {
        let cardSize = LiquidGlassCityCard.floatingSize(for: dynamicTypeSize)

        ScrollView(.horizontal) {
            LazyHStack(spacing: Self.edgeInset) {
                ForEach(cities) { city in
                    LiquidGlassCityCard(
                        city: city,
                        weather: weatherProvider(city),
                        alarms: alarmsProvider(city),
                        style: .floating,
                        onSelect: { onSelectCity(city) }
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation { onUnpinCity(city) }
                        } label: {
                            Label("Unpin \(city.name)", systemImage: "pin.slash")
                        }
                    }
                }
                AddCityCardButton(style: .floating, onTap: onAddCityTap)
            }
            .scrollTargetLayout()
        }
        .opacity(isUnderSheet ? 0 : 1)
        .allowsHitTesting(!isUnderSheet)
        // Margins rather than padding, so every card snaps into the same place.
        .contentMargins(Self.edgeInset, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition($position, anchor: .leading)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .onGeometryChange(for: CGFloat.self) { [inset = Self.edgeInset] proxy in
            let restingFrame = CGRect(x: inset, y: proxy.size.height - inset - cardSize.height,
                                      width: cardSize.width, height: cardSize.height)
            return proxy.concentricCornerRadii(in: restingFrame)?.bottomLeading ?? 0
        } action: { radius in
            cornerRadius = max(LiquidGlassCityCard.minimumCornerRadius, radius)
        }
        .environment(\.floatingCardCornerRadius, cornerRadius)
        .dynamicTypeSize(...LiquidGlassCityCard.largestFloatingTypeSize)
    }
}

/// The last card in the city list: pins another city.
struct AddCityCardButton: View {
    var style: LiquidGlassCityCard.Style = .floating
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.floatingCardCornerRadius) private var floatingCornerRadius

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.tint)
                Text("Add City")
                    .font(.headline)
            }
            .modifier(AddCardFrame(style: style, side: LiquidGlassCityCard.floatingSize(for: dynamicTypeSize).height))
            .modifier(AddCardSurface(style: style, cornerRadius: cornerRadius))
        }
        .buttonStyle(CardButtonStyle(cornerRadius: cornerRadius))
        .accessibilityLabel("Add City")
    }

    private var cornerRadius: CGFloat {
        style == .floating ? floatingCornerRadius : LiquidGlassCityCard.minimumCornerRadius
    }
}

/// Square beside the floating cards; a full-width row in the list.
private struct AddCardFrame: ViewModifier {
    let style: LiquidGlassCityCard.Style
    let side: CGFloat

    func body(content: Content) -> some View {
        switch style {
        case .floating:
            content.frame(width: side, height: side)
        case .inline:
            content.frame(maxWidth: .infinity, minHeight: 96)
        }
    }
}

private struct AddCardSurface: ViewModifier {
    let style: LiquidGlassCityCard.Style
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        switch style {
        case .floating:
            content.floatingGlass(cornerRadius: cornerRadius)
        case .inline:
            content.contentCard(cornerRadius: cornerRadius)
        }
    }
}
