import SwiftUI

/// A city at a glance, in order of what people look for:
/// 1. where it is and what time it is there (name + large clock),
/// 2. how it compares to here (day and hour offset),
/// 3. what it's like outside (condition symbol, temperature, today's high and low),
/// 4. what's set to ring (alarm count and the next one).
/// The whole card opens the city; alarms are changed in the detail view.
///
/// The name, time and offset sit together at the top. The alarms sit on the bottom edge,
/// set apart by space rather than a line. Text keeps the same distance from every edge,
/// and moves further in when the card's corners are larger.
struct LiquidGlassCityCard: View {
    enum Style {
        /// Floats over the globe: real Liquid Glass.
        case floating
        /// Sits in a scrolling list: a quiet content surface.
        case inline
    }

    /// Floating cards have a set size, so the carousel and the globe above it can be laid out
    /// before the cards are. They grow with Dynamic Type up to the largest standard size;
    /// beyond that, the city's detail view (which scales fully) is a tap away.
    static let largestFloatingTypeSize = DynamicTypeSize.xxxLarge

    /// The floating card's height at the default text size.
    static let baseHeight: CGFloat = 156

    /// List cards' corner radius, and the smallest a floating card's can be.
    nonisolated static let minimumCornerRadius: CGFloat = 26

    static func floatingSize(for typeSize: DynamicTypeSize) -> CGSize {
        let step: CGFloat = switch min(typeSize, largestFloatingTypeSize) {
        case .xLarge: 1
        case .xxLarge: 2
        case .xxxLarge: 3
        default: 0
        }
        return CGSize(width: 248 + 16 * step, height: baseHeight + 14 * step)
    }

    let city: PinnedCity
    let weather: WeatherState
    let alarms: [CityAlarm]
    var style: Style = .floating
    let onSelect: () -> Void

    @State private var settings = AppSettings.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.floatingCardCornerRadius) private var floatingCornerRadius

    /// A line of text has a little empty space above its capitals and below its baseline,
    /// about 4 points at the headline size. The top and bottom padding leave that space out,
    /// so the text looks as far from the top and bottom edges as from the sides.
    @ScaledMetric(relativeTo: .headline) private var textLineSpace: CGFloat = 4

    var body: some View {
        TimelineView(.everyMinute) { context in
            Button(action: onSelect) {
                content(date: context.date)
                    .padding(.horizontal, contentInset)
                    .padding(.vertical, max(8, contentInset - textLineSpace))
                    .modifier(CardFrame(style: style, floatingSize: Self.floatingSize(for: dynamicTypeSize)))
                    .modifier(CardSurface(style: style, cornerRadius: cornerRadius, isDaytime: isDaytime(at: context.date)))
            }
            .buttonStyle(CardButtonStyle(cornerRadius: cornerRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(date: context.date))
            .accessibilityHint(Text("Shows weather and alarms"))
            .accessibilityAddTraits(.isButton)
        }
        #if os(iOS) || os(visionOS)
        // A long press lifts the card in its own shape. (Mac context menus have no lift preview.)
        .contentShape(.contextMenuPreview, .rect(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    /// Floating cards share the radius their carousel sets; list cards use the standard one.
    private var cornerRadius: CGFloat {
        style == .floating ? floatingCornerRadius : Self.minimumCornerRadius
    }

    /// How far the content sits in from the card's edges. Larger corners curve further in,
    /// so the content moves in with them and stays clear of the curve. It's never less than
    /// the 16 points widgets use.
    private var contentInset: CGFloat {
        max(16, (cornerRadius / 2).rounded(.down))
    }

    private func content(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CardRow {
                Text(city.name)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            } trailing: {
                currentConditions
                    .fixedSize()
            }

            Text(timeText(date: date))
                .font(.system(.largeTitle, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .animation(.snappy, value: date)

            CardRow {
                Text("\(city.dayDifferenceStatus(date: date)), \(city.relativeTimeDifference(date: date))")
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .layoutPriority(1)
            } trailing: {
                highLow
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            // Space sets the alarms apart, and on a floating card keeps them on the bottom edge.
            Spacer(minLength: 16)

            alarmSummary(date: date)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The time, with AM/PM set smaller, as the Clock app shows it.
    private func timeText(date: Date) -> AttributedString {
        var time = settings.formatTimeParts(date: date, in: city.timeZone)
        let dayPeriods = time.runs[\.dateField].compactMap { field, range in
            field == .amPM ? range : nil
        }
        for range in dayPeriods {
            time[range].font = Font.headline
        }
        return time
    }

    // MARK: Weather

    /// Set at the same size and weight as the city name, so the top row reads as one line.
    @ViewBuilder
    private var currentConditions: some View {
        switch weather {
        case .loaded(let report):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: report.symbolName)
                    .symbolRenderingMode(.multicolor)
                Text(settings.formatTemperature(report.temperature))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.headline)
            .transition(.opacity)
        case .loading:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "cloud.fill")
                Text("20°")
            }
            .font(.headline)
            .redacted(reason: .placeholder)
        case .unavailable:
            Image(systemName: "icloud.slash")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var highLow: some View {
        if let report = weather.report {
            ViewThatFits {
                Text("H:\(settings.formatTemperature(report.highTemperature)) L:\(settings.formatTemperature(report.lowTemperature))")
                Text("H:\(settings.formatTemperature(report.highTemperature))")
                EmptyView()
            }
            .monospacedDigit()
            .lineLimit(1)
        }
    }

    // MARK: Alarms

    private func alarmSummary(date: Date) -> some View {
        let enabled = alarms.filter(\.isEnabled)
        let next = enabled.compactMap { $0.nextTriggerDate(from: date) }.min()
        return CardRow {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: enabled.isEmpty ? "alarm" : "alarm.fill")
                    .foregroundStyle(enabled.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                Text(alarmCountText)
                    .foregroundStyle(alarms.isEmpty ? .secondary : .primary)
            }
        } trailing: {
            if let next {
                // In the city's time, as the alarm was set, and in the app's 12/24-hour style.
                Text(settings.formatTime(date: next, in: city.timeZone))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if !alarms.isEmpty {
                Text("Off")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    private var alarmCountText: String {
        switch alarms.count {
        case 0: String(localized: "No Alarms")
        case 1: String(localized: "1 Alarm")
        default: String(localized: "\(alarms.count) Alarms")
        }
    }

    /// Daytime in the city: between today's sunrise and sunset when the forecast has them,
    /// otherwise the current reading, otherwise 6 AM–6 PM local time.
    private func isDaytime(at date: Date) -> Bool {
        if let report = weather.report {
            if let sunrise = report.sunrise, let sunset = report.sunset {
                return date >= sunrise && date < sunset
            }
            return report.isDaylight
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.timeZone
        return (6..<18).contains(calendar.component(.hour, from: date))
    }

    private func accessibilityLabel(date: Date) -> Text {
        var parts = [city.name, settings.formatTime(date: date, in: city.timeZone), city.relativeTimeDescription(date: date)]
        if let report = weather.report {
            parts.append("\(report.conditionDescription), \(settings.formatTemperature(report.temperature))")
        }
        parts.append(alarmCountText)
        if let next = alarms.filter(\.isEnabled).compactMap({ $0.nextTriggerDate(from: date) }).min() {
            parts.append(String(localized: "next at \(settings.formatTime(date: next, in: city.timeZone))"))
        }
        return Text(parts.joined(separator: ", "))
    }
}

/// A row with something at each end, sharing one baseline. At accessibility text sizes,
/// where the two would crowd each other, the trailing one moves under the leading one.
private struct CardRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                leading
                trailing
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                leading
                Spacer(minLength: 8)
                trailing
            }
        }
    }
}

/// Floating cards have a set size. List cards fill the list's width and are as tall as their text.
private struct CardFrame: ViewModifier {
    let style: LiquidGlassCityCard.Style
    let floatingSize: CGSize

    func body(content: Content) -> some View {
        switch style {
        case .floating:
            content.frame(width: floatingSize.width, height: floatingSize.height)
        case .inline:
            content.frame(maxWidth: .infinity)
        }
    }
}

/// Night cards keep the plain glass; day cards get a white tint, so day and night read at a glance.
private struct CardSurface: ViewModifier {
    let style: LiquidGlassCityCard.Style
    let cornerRadius: CGFloat
    let isDaytime: Bool

    func body(content: Content) -> some View {
        switch style {
        case .floating:
            content.floatingGlass(cornerRadius: cornerRadius, tint: isDaytime ? .white : nil)
        case .inline:
            content.contentCard(cornerRadius: cornerRadius, tint: isDaytime ? .white : nil)
        }
    }
}

/// How cards respond to a touch: they press in a little and spring back, as cards do across iOS.
/// The surface is part of the label, so the whole card moves as one and never changes shape;
/// taps and the pointer highlight follow the same shape.
struct CardButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(shape)
            #if os(iOS) || os(visionOS)
            .contentShape(.hoverEffect, shape)
            .hoverEffect()
            #endif
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.25), value: configuration.isPressed)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

extension EnvironmentValues {
    /// The floating cards' shared corner radius (see CityCardsCarouselView).
    @Entry var floatingCardCornerRadius: CGFloat = 26
}
