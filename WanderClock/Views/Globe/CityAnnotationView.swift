import SwiftUI

/// A city marker on the globe: a dot centred on the city with its name underneath, in the style of Maps.
struct CityAnnotationView: View {
    let city: PinnedCity
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(isSelected ? Color.cyan : .white)
                .frame(width: 10, height: 10)
                .overlay { Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1) }
                // A 44 pt target around the small dot, so it's easy to hit.
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .overlay(alignment: .top) {
                    Text(city.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                        .fixedSize()
                        .offset(y: 32)
                        .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
        .accessibilityLabel(Text("\(city.name), \(city.country)"))
        .accessibilityHint(Text("Shows local time, weather and alarms"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
