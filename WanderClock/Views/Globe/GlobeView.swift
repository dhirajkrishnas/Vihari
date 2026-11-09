import SwiftUI
import MapKit

struct GlobeView: View {
    let cities: [PinnedCity]
    let selectedCity: PinnedCity?
    /// Space below the globe in orbit (the city cards or the intro panel).
    var orbitBottomInset: CGFloat = 0
    /// Space below the Maps attribution: the city cards' height. It stays the same while the intro
    /// panel is up, because the map's insets follow it, and MapKit copes badly with inset changes
    /// while the camera moves (it draws only inside the insets and misreports its zoom limit).
    var attributionBottomInset: CGFloat = 0
    /// Height of the detail panel or sheet covering the bottom while a city is open.
    var detailBottomInset: CGFloat = 0
    /// Where the space for the city starts at the top, below the city's name.
    var detailTopInset: CGFloat = 56
    /// Side-by-side layouts: how much of the window's trailing side the city list covers (a city's
    /// detail opens in the same place). The globe and the city are framed in the space beside it;
    /// while a city is open the map reaches under it too, so the map fills the window.
    var trailingPaneWidth: CGFloat = 0
    /// False while the introduction has the window to itself; the globe is framed in all of it then.
    var showsTrailingPane = true
    /// iPhone: the map fills the screen in every view. Side-by-side layouts size the map to fit the
    /// globe beside the pane in orbit, and the starfield behind shows around it.
    var fillsScreen = false
    let onSelectCity: (PinnedCity) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Room left for the status bar and the floating buttons above the globe.
    private static let topClearance: CGFloat = 64

    @State private var engine = GlobeCameraEngine()

    var body: some View {
        GeometryReader { proxy in
            let layout = Layout(size: proxy.size, orbitBottomInset: orbitBottomInset, attributionBottomInset: attributionBottomInset,
                                detailBottomInset: detailBottomInset, detailTopInset: detailTopInset,
                                trailingPaneWidth: trailingPaneWidth, showsTrailingPane: showsTrailingPane, fillsScreen: fillsScreen)
            let blend = CGFloat(engine.detailBlend)
            let height = layout.orbitHeight + (layout.detailHeight - layout.orbitHeight) * blend
            let bottom = layout.orbitBottom + (layout.detailBottom - layout.orbitBottom) * blend
            // Beside a side pane the map reaches under it once the globe is big (see MapFrame).
            let reach = CGFloat(engine.reach)
            let width = layout.width + layout.extraWidth * reach
            // Its edge under the pane fades into the stars, until it reaches the window's edge.
            let sideFade = layout.extraWidth > 0 ? layout.edgeFade * (1 - reach) / max(1, width) : 0

            map
                // MapKit doesn't follow inset changes while the camera moves every frame, so the
                // insets stay fixed. On iPhone the frame stays put too, and the camera does the
                // framing; beside a side pane the frame grows, and the engine scales the camera
                // distance with its height so the zoom still follows its curve.
                .safeAreaPadding(.vertical, layout.inset)
                .frame(width: width, height: height)
                .opacity(engine.mapOpacity)
                // A fitted map (side-by-side layouts) softens its top edge in orbit and its edge under
                // the pane, so MapKit's space blends into the starfield behind it.
                .mask {
                    LinearGradient(stops: [
                        .init(color: fillsScreen ? .black : .black.opacity(blend), location: 0),
                        .init(color: .black, location: fillsScreen ? 0 : 0.12 * (1 - blend)),
                        .init(color: .black, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 1 - sideFade),
                        .init(color: .black.opacity(sideFade > 0 ? 0 : 1), location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                }
                // The map's leading edge stays at the window's, with the Maps attribution.
                .position(x: width / 2, y: bottom - height / 2)
                .onAppear { engine.layoutDidChange(frame: layout.mapFrame) }
                .onChange(of: layout) { engine.layoutDidChange(frame: layout.mapFrame) }
                .animation(.smooth(duration: 0.6), value: orbitBottomInset)
                .task(id: PrewarmRequest(cities: cities.map(\.id), frame: layout.mapFrame)) {
                    // Give the visible globe a head start, and let a window resize settle.
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    GlobeImageryPrewarmer.shared.prewarm(cities, frame: layout.mapFrame,
                                                         orbitDistance: engine.orbitDistance,
                                                         startLongitude: engine.longitude)
                }
        }
        .onAppear {
            engine.reduceMotion = reduceMotion
            engine.jump(toCity: selectedCity?.coordinate)
            engine.setActive(scenePhase == .active)
        }
        .onDisappear { engine.setActive(false) }
        .onChange(of: scenePhase) { _, phase in engine.setActive(phase == .active) }
        .onChange(of: reduceMotion) { _, value in
            engine.reduceMotion = value
            engine.setActive(scenePhase == .active)
        }
        .onChange(of: selectedCity?.id) { _, newID in
            if let newID, let city = cities.first(where: { $0.id == newID }) {
                GlobeImageryPrewarmer.shared.prioritize(city.id)
                engine.fly(to: city.coordinate)
            } else {
                engine.returnToOrbit()
            }
        }
    }

    private var map: some View {
        // The globe is display-only: touches never stop or steer it. City markers stay tappable.
        Map(position: .constant(engine.position), interactionModes: []) {
            ForEach(cities) { city in
                Annotation(city.name, coordinate: city.coordinate, anchor: .center) {
                    CityAnnotationView(city: city, isSelected: selectedCity?.id == city.id) {
                        onSelectCity(city)
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .continuous) { context in
            engine.observe(context.camera)
        }
    }

    private struct PrewarmRequest: Equatable {
        let cities: [UUID]
        let frame: GlobeCameraEngine.MapFrame
    }

    /// Where the map sits. The insets never change (MapKit doesn't follow inset changes while the
    /// camera moves every frame).
    ///
    /// At its farthest zoom MapKit always draws the Earth centred in the map view, at a fixed
    /// share of the view's height (for a view no wider than it's tall), whatever the insets.
    /// So the globe is placed by placing the view.
    private struct Layout: Equatable {
        /// The map's width in orbit: the space beside a side pane, or the whole screen.
        let width: CGFloat
        /// How much wider the map gets while a city is open: the side pane's width.
        let extraWidth: CGFloat
        let orbitHeight: CGFloat
        let orbitBottom: CGFloat
        let detailHeight: CGFloat
        let detailBottom: CGFloat
        /// Equal top and bottom insets, so the camera's centre stays at the centre of the globe.
        let inset: CGFloat
        /// iPhone city view: how far above the map's middle the city sits, so it's above the sheet.
        let focusLift: CGFloat
        /// Side-by-side layouts: the globe sizes at which the map spreads under the pane (see MapFrame).
        let reachStart: CGFloat
        let reachEnd: CGFloat
        /// Side-by-side layouts: how wide the map's fading edge under the pane is in orbit. It stops
        /// short of the globe.
        let edgeFade: CGFloat

        var mapFrame: GlobeCameraEngine.MapFrame {
            .init(width: width, extraWidth: extraWidth, orbitHeight: orbitHeight, detailHeight: detailHeight,
                  focusLift: focusLift, reachStart: reachStart, reachEnd: reachEnd)
        }

        /// The Earth's diameter as a share of the map view's height, at the farthest zoom.
        private static let fullScreenGlobeRatio: CGFloat = 0.527
        private static let fittedGlobeRatio: CGFloat = 0.56

        init(size: CGSize, orbitBottomInset: CGFloat, attributionBottomInset: CGFloat, detailBottomInset: CGFloat,
             detailTopInset: CGFloat, trailingPaneWidth: CGFloat, showsTrailingPane: Bool, fillsScreen: Bool) {
            let paneWidth = showsTrailingPane ? trailingPaneWidth : 0
            width = size.width - paneWidth
            extraWidth = paneWidth

            // The Maps attribution sits just above the cards.
            let attributionY = size.height - attributionBottomInset - 4
            var diameter = size.width
            if fillsScreen {
                // Cover the whole screen, and run past the top just far enough that the globe
                // clears the cards (or the intro panel) and the attribution.
                // MapKit draws the attribution label about 30 pt above the bottom inset.
                let globeBottom = size.height - orbitBottomInset - 44
                let needed = (size.height - globeBottom) / (0.5 - Self.fullScreenGlobeRatio / 2)
                orbitHeight = min(max(size.height, needed), size.height * 1.2)
                orbitBottom = size.height
            } else {
                // Side-by-side layouts: size the map so the globe fits the space beside the pane.
                diameter = max(160, min(width - 32, attributionY - GlobeView.topClearance - 12))
                orbitHeight = diameter / Self.fittedGlobeRatio
                let globeCenterY = (GlobeView.topClearance + attributionY) / 2
                orbitBottom = globeCenterY + orbitHeight / 2
            }
            inset = max(0, orbitBottom - attributionY)
            edgeFade = max(8, min(32, (width - diameter) / 2 - 2))

            // City view: the city sits midway between its name and the panel, or the window's bottom.
            let panelTop = size.height - detailBottomInset
            if fillsScreen {
                // The map keeps its frame, so it still fills the screen behind the sheet; the camera
                // lifts the city above the sheet instead.
                detailHeight = orbitHeight
                detailBottom = orbitBottom
                focusLift = (orbitBottom - orbitHeight / 2) - (detailTopInset + panelTop) / 2
                reachStart = 0
                reachEnd = 0
            } else {
                // The map runs on behind the panel, and is centred on the city, so the city sits no
                // lower than leaves the map's top edge at the window's.
                detailBottom = panelTop + inset
                let cityY = min(detailTopInset + panelTop, panelTop + inset) / 2
                detailHeight = max(120, 2 * (detailBottom - cityY))
                focusLift = 0
                // The globe covers the space beside the pane once it reaches that space's farthest
                // corner from the city.
                let corner = hypot(width / 2, max(cityY, size.height - cityY))
                reachStart = corner * 1.3
                reachEnd = corner * 4
            }
        }
    }
}

/// Fetches the satellite imagery the globe is about to show, so it comes from the system's
/// tile cache instead of the network when the camera gets there, rather than arriving in patches.
///
/// MapKit has no API for downloading imagery ahead of time (the whole planet is far too big
/// anyway), but a snapshot loads the same tiles and terrain that a map view of that size loads
/// for that camera, and the system keeps them in its tile cache. So this takes snapshots, one at
/// a time and at the map's real size, of:
/// - the whole globe from orbit, from eight sides, starting with the side drifting into view;
/// - each city's descent, at every zoom level the flight passes through.
/// A city that's just been opened jumps the queue. In Low Data Mode only the globe is fetched.
@MainActor
final class GlobeImageryPrewarmer {
    static let shared = GlobeImageryPrewarmer()

    private struct Job {
        let key: String
        let cityID: UUID?
        let camera: MKMapCamera
        let size: CGSize
    }

    private var queue: [Job] = []
    private var finished: Set<String> = []
    private var worker: Task<Void, Never>?
    private var running: (job: Job, snapshotter: MKMapSnapshotter)?
    /// The job set aside for a city that was just opened, to be tried again later.
    private var setAside: String?

    /// Queues everything not yet fetched for these cities, for a map with this frame
    /// (which, with the camera, decides the tiles MapKit loads).
    func prewarm(_ cities: [PinnedCity], frame: GlobeCameraEngine.MapFrame, orbitDistance: CLLocationDistance, startLongitude: Double) {
        guard frame.width > 0, frame.orbitHeight > 0, frame.detailHeight > 0 else { return }
        var jobs: [Job] = []
        // The drift moves the camera west, so start with the side just west of it and go on westward.
        let firstSide = Int((startLongitude / 45).rounded(.down))
        for step in 0..<8 {
            let longitude = Double(((firstSide - step) % 8 + 8) % 8) * 45
            let camera = GlobeCameraEngine.Camera(latitude: GlobeCameraEngine.orbitLatitude, longitude: longitude,
                                                  distance: orbitDistance, pitch: 0)
            jobs.append(job(cityID: nil, camera: camera, size: CGSize(width: frame.width, height: frame.orbitHeight)))
        }
        for city in cities {
            for sample in GlobeCameraEngine.descentSamples(to: city.coordinate, orbitDistance: orbitDistance) {
                // As the live map shows it: framed for the frame at this point of the flight.
                let framed = GlobeCameraEngine.framing(sample.camera, blend: sample.blend, in: frame)
                let size = CGSize(width: frame.width + frame.extraWidth * framed.reach, height: frame.height(at: sample.blend))
                jobs.append(job(cityID: city.id, camera: framed.camera, size: size))
            }
        }
        queue = jobs.filter { !finished.contains($0.key) && $0.key != running?.job.key }
        startWorker()
    }

    /// Moves a city's descent to the front, setting aside a snapshot of somewhere else.
    func prioritize(_ cityID: UUID) {
        let first = queue.filter { $0.cityID == cityID }
        guard !first.isEmpty else { return }
        queue = first + queue.filter { $0.cityID != cityID }
        if let running, running.job.cityID != cityID {
            setAside = running.job.key
            running.snapshotter.cancel()
        }
    }

    /// Forgets everything (after Delete All Data).
    func reset() {
        queue = []
        finished = []
        running?.snapshotter.cancel()
    }

    private func job(cityID: UUID?, camera: GlobeCameraEngine.Camera, size: CGSize) -> Job {
        // The same checks the live map's camera gets (MapKit throws on a centre outside -180...180).
        let valid = camera.mapCamera
        let key = [valid.centerCoordinate.latitude * 100, valid.centerCoordinate.longitude * 100,
                   valid.distance / 1000, valid.pitch, size.width / 10, size.height / 10]
            .map { String(Int($0.rounded())) }
            .joined(separator: ",")
        let snapshotCamera = MKMapCamera(lookingAtCenter: valid.centerCoordinate, fromDistance: valid.distance,
                                         pitch: valid.pitch, heading: 0)
        return Job(key: key, cityID: cityID, camera: snapshotCamera, size: size)
    }

    private func startWorker() {
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task {
            while !queue.isEmpty {
                let job = queue.removeFirst()
                if job.cityID != nil, NetworkStatus.shared.isConstrained { continue }
                let options = MKMapSnapshotter.Options()
                options.camera = job.camera
                options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
                options.size = job.size
                let snapshotter = MKMapSnapshotter(options: options)
                running = (job, snapshotter)
                do {
                    _ = try await snapshotter.start()
                    finished.insert(job.key)
                } catch {
                    // Set aside for another city: try again later. Offline or failed: the next
                    // prewarm request tries again.
                    if setAside == job.key { queue.append(job) }
                }
                setAside = nil
                running = nil
                // Leave the network and GPU to the live globe for a moment between snapshots.
                try? await Task.sleep(for: .milliseconds(150))
            }
            worker = nil
        }
    }
}
