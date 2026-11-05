import SwiftUI

/// The plain backdrop of space behind the globe.
struct StarryBackgroundView: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
