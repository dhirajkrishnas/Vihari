import SwiftUI

/// Space behind the globe: black with a scattering of faint stars, like the sky MapKit draws around
/// the globe. Beside a side pane the map only spans part of the window in orbit, so this sky
/// carries on behind the pane and the window reads as one view of space.
struct StarryBackgroundView: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            // The sky is laid out in fixed tiles from the top-left corner, so the stars stay where
            // they are when the window changes size.
            let tile = Self.tileSize
            for column in 0..<Int((size.width / tile).rounded(.up)) {
                for row in 0..<Int((size.height / tile).rounded(.up)) {
                    var random = SplitMix(seed: UInt64(column) &* 0x9E37_79B9 &+ UInt64(row) &* 0x85EB_CA6B &+ 0x5EED)
                    for _ in 0..<Self.starsPerTile {
                        let x = (Double(column) + random.unit()) * tile
                        let y = (Double(row) + random.unit()) * tile
                        // Most stars are faint pinpricks; a few are brighter and a little larger.
                        let brightness = random.unit()
                        let radius = 0.35 + 0.5 * brightness * brightness * brightness
                        context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)),
                                     with: .color(.white.opacity(0.3 + 0.6 * brightness)))
                    }
                }
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static let tileSize = 240.0
    /// About one star per 2,800 square points, as in MapKit's sky.
    private static let starsPerTile = 20
}

/// A small, fast random number generator with a fixed seed, so the stars come out the same every time.
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A number in 0..<1.
    mutating func unit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
