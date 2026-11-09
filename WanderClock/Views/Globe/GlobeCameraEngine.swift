import SwiftUI
import MapKit
import QuartzCore
#if os(macOS)
import AppKit
#endif

/// Drives the globe camera one display frame at a time: the slow orbit drift, and flights
/// between orbit and a city, or from one city to another. Every frame sets the camera
/// directly (no implicit animation), so the motion stays smooth and keeps running while lists scroll.
///
/// With Reduce Motion on, the globe holds still and flights become a short dissolve.
@Observable
final class GlobeCameraEngine {
    nonisolated struct Camera: Equatable {
        var latitude: Double
        var longitude: Double
        var distance: CLLocationDistance
        var pitch: Double

        /// The camera as MapKit takes it. A flight lets the longitude run past ±180° so it can take
        /// the short way across the 180th meridian, but MapKit throws (and the app crashes) on a
        /// centre outside -180...180, so it's wrapped here, and the other values are kept valid too.
        var mapCamera: MapCamera {
            MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: min(90, max(-90, latitude)),
                                                               longitude: Self.wrapped(longitude)),
                      distance: distance.isFinite && distance > 0 ? distance : GlobeCameraEngine.requestedOrbitDistance,
                      heading: 0,
                      pitch: pitch.isFinite ? max(0, pitch) : 0)
        }

        /// The same longitude, within -180...180.
        static func wrapped(_ longitude: Double) -> Double {
            guard longitude.isFinite else { return 0 }
            var value = longitude.truncatingRemainder(dividingBy: 360)
            if value > 180 { value -= 360 }
            if value < -180 { value += 360 }
            return value
        }

        /// Moves the centre east, so the old centre shows `arc` (radians, seen from the Earth's
        /// centre) to the left of the new one, level with it. That puts the new centre where the
        /// ground line through the old one runs due east-west (it's that line's nearest point to
        /// the pole); this can't quite be done close to the poles, so the latitude stops short of them.
        mutating func moveCentreEast(byArc arc: Double) {
            let lat = latitude * .pi / 180
            let newLat = asin(min(1, max(-1, sin(lat) / cos(arc))))
            let capped = min(85 * Double.pi / 180, max(-85 * Double.pi / 180, newLat))
            latitude = capped * 180 / .pi
            longitude += atan2(sin(arc), cos(arc) * cos(capped)) * 180 / .pi
        }

        /// Moves the centre south along its meridian by `arc` radians, so the old centre shows
        /// straight above the new one. Near the South Pole it eases to a stop instead of passing it.
        mutating func moveCentreSouth(byArc arc: Double) {
            let target = latitude - arc * 180 / .pi
            latitude = target < -80 ? -80 - 9 * tanh((-80 - target) / 9) : target
        }
    }

    /// What the camera needs to know about the map view's frame.
    ///
    /// iPhone: the map fills the screen in every view. In the city view the camera looks a little
    /// south of the city, so the city sits above the sheet (`focusLift`).
    ///
    /// Side-by-side layouts: in orbit the map spans the space beside the side pane, with the globe
    /// centred in it. While a city is open the map reaches under the pane, so it fills the window.
    /// It can't simply span the window throughout: MapKit draws a wider map's Earth larger at its
    /// farthest zoom, and centred in the map, so the globe wouldn't fit beside the pane.
    nonisolated struct MapFrame: Equatable {
        /// The map's width in orbit.
        var width: Double = 0
        /// How much wider it gets while a city is open: the side pane's width (0 on iPhone).
        var extraWidth: Double = 0
        var orbitHeight: Double = 0
        var detailHeight: Double = 0
        /// City view: how far above the map's centre the city sits, in points.
        var focusLift: Double = 0
        /// Side-by-side layouts: the globe's radius on screen (points) at which the map starts to
        /// reach under the pane, and at which it fills the window. By then the globe covers the space
        /// beside the pane, so the map can move without moving the city or showing the globe's edge.
        var reachStart: Double = 0
        var reachEnd: Double = 0

        /// Detail frame height over orbit frame height; 1 until the view has a size
        /// (a zero height would make it infinite, and the camera distance invalid).
        var detailRatio: Double { orbitHeight > 0 ? detailHeight / orbitHeight : 1 }

        func height(at blend: Double) -> Double {
            orbitHeight + (detailHeight - orbitHeight) * blend
        }
    }

    static let orbitLatitude = 12.0
    /// A request beyond MapKit's farthest zoom. MapKit clamps it; the real limit is measured
    /// from the map so flights don't spend time "descending" inside the clamp.
    nonisolated static let requestedOrbitDistance: CLLocationDistance = 40_000_000
    static let cityDistance: CLLocationDistance = 650_000
    static let cityPitch = 35.0
    private static let driftDegreesPerSecond = 2.0

    /// The camera the map shows.
    private(set) var position: MapCameraPosition
    /// 0 frames the globe for orbit, 1 frames the city above the detail panel.
    private(set) var detailBlend: Double = 0
    /// Below 1 only while a Reduce Motion dissolve hides the map to change views.
    private(set) var mapOpacity: Double = 1

    /// How far the map reaches under a side pane: 0 in orbit, 1 (the whole window) once the globe
    /// covers the space beside the pane. See MapFrame.
    private(set) var reach: Double = 0

    @ObservationIgnored var reduceMotion = false
    /// The map view's frame (see MapFrame).
    @ObservationIgnored private(set) var mapFrame = MapFrame()
    /// MapKit's farthest zoom, once measured.
    @ObservationIgnored private(set) var orbitDistance = requestedOrbitDistance
    /// When the map's frame or insets last changed. While they settle, MapKit can report a far
    /// nearer zoom limit than it really has, so measuring waits.
    @ObservationIgnored private var layoutChangedAt: CFTimeInterval = 0
    @ObservationIgnored private var camera: Camera
    @ObservationIgnored private var flight: Flight?
    @ObservationIgnored private var flightStart: CFTimeInterval?
    @ObservationIgnored private var isInOrbit = true
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var driftSpeed = 0.0
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private let ticker = FrameTicker()
    @ObservationIgnored private var powerObserver: NSObjectProtocol?

    /// The longitude below the camera, so imagery prefetching can start with the side drifting into view.
    var longitude: Double { camera.longitude }

    init() {
        let start = Camera(latitude: Self.orbitLatitude, longitude: 20, distance: Self.requestedOrbitDistance, pitch: 0)
        camera = start
        position = .camera(start.mapCamera)
        ticker.onFrame = { [weak self] timestamp in self?.tick(timestamp) }
        // Low Power Mode slows the drift's frame rate.
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTicker() }
        }
    }

    // MARK: Lifecycle

    func setActive(_ active: Bool) {
        isActive = active
        lastTimestamp = nil
        updateTicker()
    }

    /// Called with the map's real camera, to learn MapKit's zoom-out limit (what it shows in orbit;
    /// see enterOrbit()). It's tracked both ways, so one bad reading can't leave flights stopping short.
    func observe(_ mapCamera: MapCamera) {
        guard isInOrbit, flight == nil, detailBlend == 0, camera.pitch == 0,
              CACurrentMediaTime() - layoutChangedAt > 1 else { return }
        let actual = mapCamera.distance
        if actual.isFinite, actual > 1_000_000 { orbitDistance = min(actual, Self.requestedOrbitDistance) }
    }

    /// Called when the map's frame or insets change.
    func layoutDidChange(frame: MapFrame) {
        layoutChangedAt = CACurrentMediaTime()
        guard frame != mapFrame else { return }
        mapFrame = frame
        // Follow the new frame now, even while the camera is still.
        show()
    }

    // MARK: Flights

    /// Jumps straight to a state (first appearance, or a new layout after the window changes shape).
    func jump(toCity coordinate: CLLocationCoordinate2D?) {
        flight = nil
        mapOpacity = 1
        if let coordinate {
            let target = Camera(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                distance: Self.cityDistance, pitch: Self.cityPitch)
            isInOrbit = false
            detailBlend = 1
            // A map that starts out on a still camera can stay blank (a grey grid, no markers)
            // until its camera moves, so the city settles in with a short, gentle zoom.
            camera = target
            camera.distance *= reduceMotion ? 1.02 : 1.25
            start(Flight(kind: .descend, from: camera, to: target, fromBlend: 1, toBlend: 1, duration: 0.9))
        } else {
            camera.latitude = Self.orbitLatitude
            camera.pitch = 0
            detailBlend = 0
            enterOrbit()
        }
        show()
        updateTicker()
    }

    /// In orbit the camera asks for more than MapKit allows, so MapKit shows its farthest zoom
    /// (the flight up ends right at it) and observe(_:) can measure that limit.
    private func enterOrbit() {
        isInOrbit = true
        camera.distance = Self.requestedOrbitDistance
    }

    func fly(to coordinate: CLLocationCoordinate2D) {
        var from = camera
        from.distance = min(from.distance, orbitDistance)
        var target = Camera(latitude: coordinate.latitude, longitude: coordinate.longitude,
                            distance: Self.cityDistance, pitch: Self.cityPitch)
        // Take the short way around.
        target.longitude = from.longitude + Self.shortestDelta(from: from.longitude, to: target.longitude)

        if reduceMotion {
            start(Flight(kind: .dissolve, from: from, to: target, fromBlend: detailBlend, toBlend: 1, duration: 0.5))
        } else if !isInOrbit, flight == nil {
            // City to city: rise just high enough to take in both, then come down.
            let arc = Self.arcDegrees(from: from, to: target)
            let peak = min(orbitDistance, max(Self.cityDistance * 1.5, arc * 111_000 * 1.4))
            start(Flight(kind: .hop, from: from, to: target, fromBlend: detailBlend, toBlend: 1,
                         duration: 2.2 + 1.3 * min(arc, 120) / 120, peak: peak))
        } else {
            let turn = abs(target.longitude - from.longitude) + abs(target.latitude - from.latitude)
            start(Flight(kind: .descend, from: from, to: target, fromBlend: detailBlend, toBlend: 1,
                         duration: 2.6 + 0.9 * min(turn, 180) / 180))
        }
        isInOrbit = false
    }

    func returnToOrbit() {
        var from = camera
        from.distance = min(from.distance, orbitDistance)
        let target = Camera(latitude: Self.orbitLatitude, longitude: from.longitude, distance: orbitDistance, pitch: 0)
        start(Flight(kind: reduceMotion ? .dissolve : .ascend, from: from, to: target, fromBlend: detailBlend, toBlend: 0,
                     duration: reduceMotion ? 0.5 : 2.3))
    }

    private func start(_ newFlight: Flight) {
        flight = newFlight
        flightStart = nil
        driftSpeed = 0
        updateTicker()
    }

    /// The cameras a flight down to `coordinate` passes through: one for each zoom level of
    /// imagery it shows (each halving of altitude), with how far the frame has moved toward the
    /// city view. Used to fetch that imagery before the flight needs it.
    static func descentSamples(to coordinate: CLLocationCoordinate2D, orbitDistance: CLLocationDistance) -> [(camera: Camera, blend: Double)] {
        let from = Camera(latitude: coordinate.latitude, longitude: coordinate.longitude, distance: orbitDistance, pitch: 0)
        let to = Camera(latitude: coordinate.latitude, longitude: coordinate.longitude, distance: cityDistance, pitch: cityPitch)
        let descent = Flight(kind: .descend, from: from, to: to, fromBlend: 0, toBlend: 1, duration: 1)
        let steps = 240
        var samples: [(camera: Camera, blend: Double)] = []
        var nextDistance = orbitDistance / 2
        for step in 1...steps {
            let state = descent.state(at: Double(step) / Double(steps))
            if state.camera.distance <= nextDistance || step == steps {
                samples.append((state.camera, state.blend))
                while nextDistance >= state.camera.distance { nextDistance /= 2 }
            }
        }
        return samples
    }

    // MARK: Frames

    private var needsFrames: Bool {
        isActive && (flight != nil || (isInOrbit && !reduceMotion))
    }

    private func updateTicker() {
        guard needsFrames else {
            ticker.stop()
            lastTimestamp = nil
            return
        }
        // The slow drift looks the same at 30 fps; flights always get the full rate.
        let saving = flight == nil && ProcessInfo.processInfo.isLowPowerModeEnabled
        ticker.start(preferredRate: saving ? 30 : 60)
    }

    private func tick(_ timestamp: CFTimeInterval) {
        let dt = lastTimestamp.map { min(max(timestamp - $0, 0), 1 / 15) } ?? 0
        lastTimestamp = timestamp

        if let flight {
            if flightStart == nil { flightStart = timestamp }
            let progress = min(1, (timestamp - (flightStart ?? timestamp)) / flight.duration)
            let state = flight.state(at: progress)
            camera = state.camera
            if detailBlend != state.blend { detailBlend = state.blend }
            if mapOpacity != state.opacity { mapOpacity = state.opacity }
            if progress >= 1 {
                self.flight = nil
                camera.longitude = Camera.wrapped(camera.longitude)
                mapOpacity = 1
                if flight.endsInOrbit { enterOrbit() }
                updateTicker()
            }
        } else if isInOrbit, !reduceMotion {
            // Ease the drift in after a flight instead of starting at full speed.
            let target = Self.driftDegreesPerSecond
            driftSpeed = min(target, driftSpeed + target * dt / 1.5)
            // The Earth turns west to east, so the ground below a fixed viewpoint moves east and
            // the longitude under the camera falls (new land comes into view from the west).
            camera.longitude = Camera.wrapped(camera.longitude - driftSpeed * dt)
        }

        show()
        if !needsFrames { updateTicker() }
    }

    /// Gives the map the camera, framed for the map's current frame.
    private func show() {
        let framed = Self.framing(camera, blend: detailBlend, in: mapFrame)
        if reach != framed.reach { reach = framed.reach }
        position = .camera(framed.camera.mapCamera)
    }

    /// MapKit's focal length, in view heights (a vertical field of view of about 30°), measured:
    /// ground `s` metres to the side of the view's centre, `d` metres from the camera, shows
    /// `s / d × focalLength × height` points from the centre.
    private nonisolated static let focalLength = 1.86
    private nonisolated static let earthRadius = 6_371_000.0

    /// The camera as the map is given it, and how far the map reaches under a side pane.
    ///
    /// MapKit's scale follows the view height, so the distance is scaled by as much as the frame
    /// height has changed. MapKit puts the point the camera looks at in the middle of the map, so to
    /// show the city somewhere else the camera looks beside it:
    /// - iPhone: south of the city, so the city sits above the sheet. This grows with `blend`.
    /// - Beside a side pane: the map widens under the pane, so its middle moves right. The camera
    ///   looks east of the city by as much, so the city stays in the middle of the space beside the pane.
    ///   The map only reaches a little way under the pane (enough to hide the globe's edge behind it)
    ///   until the globe covers the space beside the pane; only then does it spread under the rest.
    ///   Spreading it earlier would slide the whole globe sideways while it grows.
    nonisolated static func framing(_ camera: Camera, blend: Double, in frame: MapFrame) -> (camera: Camera, reach: Double) {
        var shown = camera
        shown.distance *= 1 + (frame.detailRatio - 1) * blend
        guard frame.orbitHeight > 0 else { return (shown, 0) }
        let focal = focalLength * frame.height(at: blend)

        if frame.focusLift != 0, blend > 0 {
            shown.moveCentreSouth(byArc: verticalArc(lift: frame.focusLift * blend, focal: focal,
                                                     distance: shown.distance, pitch: shown.pitch))
        }

        guard frame.extraWidth > 0 else { return (shown, 0) }
        let radius = globeRadius(distance: shown.distance, pitch: shown.pitch, focal: focal)
        let shift = paneShift(globeRadius: radius, in: frame)
        guard shift > 0 else { return (shown, 0) }
        shown.moveCentreEast(byArc: groundArc(across: shift, focal: focal, distance: shown.distance))
        return (shown, min(1, 2 * shift / frame.extraWidth))
    }

    /// How far the map's middle moves right of the middle of the space beside a side pane, in points:
    /// half the extra width the map reaches under the pane.
    private nonisolated static func paneShift(globeRadius radius: Double, in frame: MapFrame) -> Double {
        let half = frame.extraWidth / 2
        // Once the globe is wider than the space beside the pane, the map reaches just under the
        // pane's glass, so the globe's edge is cut off behind the glass rather than in the open.
        let tuck = min(half, paneTuck)
        let tucked = tuck * smoothstep((radius - (frame.width / 2 - paneTuck)) / paneTuck)
        // Once the globe covers the space beside the pane, the map spreads under the rest of it.
        guard frame.reachStart > 0, frame.reachEnd > frame.reachStart else { return tucked }
        let spread = smootherstep(log(radius / frame.reachStart) / log(frame.reachEnd / frame.reachStart))
        return tucked + (half - tucked) * spread
    }

    /// How far the map reaches under a side pane while the globe is too small to cover the space
    /// beside it, in points (half of it, as the map's middle moves by half its widening).
    private nonisolated static let paneTuck = 20.0

    /// The Earth's radius on screen, in points.
    private nonisolated static func globeRadius(distance: CLLocationDistance, pitch: Double, focal: Double) -> Double {
        let r = earthRadius
        let tilt = pitch * .pi / 180
        let centre = sqrt(r * r + distance * distance + 2 * r * distance * cos(tilt))
        return focal * r / sqrt(max(1, centre * centre - r * r))
    }

    /// The angle, seen from the Earth's centre, between the ground at the view's centre and the
    /// ground `points` to one side of it.
    private nonisolated static func groundArc(across points: Double, focal: Double, distance: CLLocationDistance) -> Double {
        let r = earthRadius
        let centre = distance + r
        let angle = atan(points / focal)
        // How far along that line of sight it meets the ground (or grazes it, at the horizon).
        let reach = centre * cos(angle) - sqrt(max(0, r * r - centre * centre * sin(angle) * sin(angle)))
        return asin(min(1, reach * sin(angle) / r))
    }

    /// The angle, seen from the Earth's centre, between the ground at the view's centre and the
    /// ground `lift` points straight above it, for a camera tilted `pitch` degrees.
    private nonisolated static func verticalArc(lift: Double, focal: Double, distance: CLLocationDistance,
                                                pitch: Double) -> Double {
        let r = earthRadius
        let tilt = pitch * .pi / 180
        // In the plane of the view's centre meridian: the Earth's centre at the origin, the ground at
        // the view's centre straight up the y axis, north along x. The camera is south of it, tilted.
        let cameraX = -distance * sin(tilt), cameraY = r + distance * cos(tilt)
        // The line of sight `lift` points above the view's centre.
        let k = lift / focal
        var dx = sin(tilt) + k * cos(tilt), dy = -cos(tilt) + k * sin(tilt)
        let length = (dx * dx + dy * dy).squareRoot()
        dx /= length
        dy /= length
        // Where it meets the ground (at the horizon if it passes over it).
        let b = cameraX * dx + cameraY * dy
        let c = cameraX * cameraX + cameraY * cameraY - r * r
        let t = -b - max(0, b * b - c).squareRoot()
        return atan2(cameraX + t * dx, cameraY + t * dy)
    }

    private nonisolated static func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    private nonisolated static func smootherstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    // MARK: Math

    private static func shortestDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    /// The angle between two points as seen from the Earth's centre, in degrees.
    private static func arcDegrees(from a: Camera, to b: Camera) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLongitude = (b.longitude - a.longitude) * .pi / 180
        let cosine = sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(deltaLongitude)
        return acos(min(1, max(-1, cosine))) * 180 / .pi
    }
}

// MARK: - Flight curve

private nonisolated struct Flight {
    enum Kind {
        /// From orbit (or mid-flight) down to a city.
        case descend
        /// From a city back up to orbit.
        case ascend
        /// From one city to another, rising in between.
        case hop
        /// Reduce Motion: fade out, change view, fade in.
        case dissolve
    }

    let kind: Kind
    let from: GlobeCameraEngine.Camera
    let to: GlobeCameraEngine.Camera
    let fromBlend: Double
    let toBlend: Double
    let duration: TimeInterval
    /// The highest point of a hop.
    var peak: CLLocationDistance = 0

    var endsInOrbit: Bool { toBlend == 0 }

    /// Staged, overlapping phases. Descending: turn to face the city, then sink toward it
    /// (slowing at the end so imagery can resolve), and tilt in the last stretch.
    /// Ascending is the reverse: level out, rise, and settle back to the orbit latitude.
    func state(at u: Double) -> (camera: GlobeCameraEngine.Camera, blend: Double, opacity: Double) {
        switch kind {
        case .descend, .ascend:
            let turn, sink, tilt, frame: Double
            if kind == .descend {
                turn = Self.ease(Self.phase(u, 0, 0.6))
                sink = Self.ease(Self.phase(u, 0.2, 1))
                tilt = Self.ease(Self.phase(u, 0.55, 1))
                frame = Self.ease(Self.phase(u, 0, 0.35))
            } else {
                tilt = Self.ease(Self.phase(u, 0, 0.4))
                sink = Self.ease(Self.phase(u, 0, 0.85))
                turn = Self.ease(Self.phase(u, 0.15, 1))
                frame = Self.ease(Self.phase(u, 0, 0.35))
            }
            var camera = from
            camera.latitude = Self.mix(from.latitude, to.latitude, turn)
            camera.longitude = Self.mix(from.longitude, to.longitude, turn)
            // Zoom in log space, so every moment covers the same apparent change in scale.
            camera.distance = exp(Self.mix(log(from.distance), log(to.distance), sink))
            camera.pitch = Self.mix(from.pitch, to.pitch, tilt)
            return (camera, Self.mix(fromBlend, toBlend, frame), 1)

        case .hop:
            let t = Self.ease(u)
            let turn = Self.ease(Self.phase(u, 0.1, 0.9))
            // 0 at both cities, 1 halfway, with no jolt at either end.
            let rise = 4 * t * (1 - t)
            let lift = max(0, log(peak) - max(log(from.distance), log(to.distance)))
            var camera = from
            camera.latitude = Self.mix(from.latitude, to.latitude, turn)
            camera.longitude = Self.mix(from.longitude, to.longitude, turn)
            camera.distance = exp(Self.mix(log(from.distance), log(to.distance), t) + lift * rise)
            // Look straight down at the top of the arc.
            camera.pitch = Self.mix(from.pitch, to.pitch, t) * (1 - rise)
            return (camera, Self.mix(fromBlend, toBlend, t), 1)

        case .dissolve:
            let swapAt = 0.4
            if u < swapAt {
                return (from, fromBlend, 1 - Self.ease(Self.phase(u, 0, swapAt)))
            }
            return (to, toBlend, Self.ease(Self.phase(u, swapAt, 1)))
        }
    }

    private static func phase(_ u: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (u - start) / (end - start)))
    }

    /// Smootherstep: zero velocity and acceleration at both ends, so phases blend seamlessly.
    private static func ease(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

// MARK: - Display link

/// Calls `onFrame` on every display refresh, in the common run-loop mode so it keeps
/// firing while a scroll view is tracking.
final class FrameTicker: NSObject {
    var onFrame: ((CFTimeInterval) -> Void)?
    private var link: CADisplayLink?
    private var preferredRate: Float = 0

    func start(preferredRate rate: Float) {
        if let link {
            if rate != preferredRate {
                preferredRate = rate
                link.preferredFrameRateRange = Self.range(rate)
            }
            return
        }
        #if os(macOS)
        guard let screen = NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        #else
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        #endif
        preferredRate = rate
        link.preferredFrameRateRange = Self.range(rate)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private static func range(_ rate: Float) -> CAFrameRateRange {
        CAFrameRateRange(minimum: rate / 2, maximum: rate, preferred: rate)
    }

    @objc private func step(_ link: CADisplayLink) {
        onFrame?(link.targetTimestamp)
    }
}
