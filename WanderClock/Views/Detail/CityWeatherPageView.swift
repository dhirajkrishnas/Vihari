import SwiftUI

struct CityWeatherPageView: View {
    let city: PinnedCity
    let weather: WeatherState
    let onRetry: () -> Void

    @State private var settings = AppSettings.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 64
    @ScaledMetric(relativeTo: .subheadline) private var dayColumnWidth: CGFloat = 60
    @ScaledMetric(relativeTo: .subheadline) private var temperatureColumnWidth: CGFloat = 44

    var body: some View {
        ScrollView(.vertical) {
            Group {
                switch weather {
                case .loaded(let report):
                    TimelineView(.everyMinute) { context in
                        content(report, now: context.date)
                    }
                case .loading:
                    ProgressView("Loading weather…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                case .unavailable:
                    ContentUnavailableView {
                        Label("Weather Unavailable", systemImage: "icloud.slash")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Try Again", action: onRetry)
                            .buttonStyle(.bordered)
                    }
                    .frame(minHeight: 280)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func content(_ report: WeatherReport, now: Date) -> some View {
        VStack(spacing: 20) {
            hero(report)
            hourly(report, now: now)
            daily(report, now: now)
            metrics(report)
            WeatherAttributionView(updated: report.lastUpdated, now: now)
        }
    }

    // MARK: Hero

    private func hero(_ report: WeatherReport) -> some View {
        VStack(spacing: 8) {
            Image(systemName: report.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: heroSize))
                .accessibilityHidden(true)

            Text(settings.formatTemperature(report.temperature))
                .font(.system(size: heroSize, weight: .thin))
                .contentTransition(.numericText())

            Text(report.conditionDescription)
                .font(.title3.weight(.medium))

            ViewThatFits {
                HStack(spacing: 12) { highLowFeelsLike(report) }
                VStack(spacing: 4) { highLowFeelsLike(report) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .contentCard(cornerRadius: 28, tint: report.category.accentColor)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func highLowFeelsLike(_ report: WeatherReport) -> some View {
        let high = settings.formatTemperature(report.highTemperature)
        let low = settings.formatTemperature(report.lowTemperature)
        Text("H:\(high)").accessibilityLabel(Text("High \(high)"))
        Text("L:\(low)").accessibilityLabel(Text("Low \(low)"))
        Text("Feels like \(settings.formatTemperature(report.feelsLike))")
    }

    // MARK: Hourly

    private func hourly(_ report: WeatherReport, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Hourly Forecast", systemImage: "clock")

            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(Array(report.upcomingHours(from: now).enumerated()), id: \.element.id) { index, item in
                        let hour = index == 0 ? String(localized: "Now") : hourLabel(item.date)
                        let temperature = settings.formatTemperature(item.temperature)
                        VStack(spacing: 8) {
                            Text(hour)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Image(systemName: item.symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(.title3)
                                .frame(minHeight: 28)
                            Text(temperature)
                                .font(.system(.subheadline, weight: .semibold))
                            Text(item.precipitationChancePercent >= 20 ? AppSettings.formatPercent(item.precipitationChancePercent) : " ")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.cyan)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(hourlyAccessibilityLabel(hour: hour, item: item, temperature: temperature))
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .contentCard(cornerRadius: 24)
    }

    private func hourlyAccessibilityLabel(hour: String, item: HourlyForecastItem, temperature: String) -> Text {
        if item.precipitationChancePercent >= 20 {
            return Text("\(hour): \(item.conditionDescription), \(temperature), \(AppSettings.formatPercent(item.precipitationChancePercent)) chance of precipitation")
        }
        return Text("\(hour): \(item.conditionDescription), \(temperature)")
    }

    // MARK: Daily

    private func daily(_ report: WeatherReport, now: Date) -> some View {
        let range = report.forecastTemperatureRange
        let days = report.upcomingDays(from: now)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "10‑Day Forecast", systemImage: "calendar")

            VStack(spacing: 12) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let name = index == 0 ? String(localized: "Today") : weekdayLabel(day.date)
                    HStack {
                        Text(name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: dayColumnWidth, alignment: .leading)

                        VStack(spacing: 0) {
                            Image(systemName: day.symbolName)
                                .symbolRenderingMode(.multicolor)
                            if day.precipitationChancePercent >= 30 {
                                Text(AppSettings.formatPercent(day.precipitationChancePercent))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.cyan)
                                    .fixedSize()
                            }
                        }
                        .frame(minWidth: 32)

                        Text(settings.formatTemperature(day.lowTemperature))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: temperatureColumnWidth, alignment: .trailing)

                        TemperatureRangeBar(low: day.lowTemperature, high: day.highTemperature, overall: range)
                            .frame(height: 20)

                        Text(settings.formatTemperature(day.highTemperature))
                            .font(.subheadline.weight(.semibold))
                            .frame(width: temperatureColumnWidth, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(name): \(day.conditionDescription), low \(settings.formatTemperature(day.lowTemperature)), high \(settings.formatTemperature(day.highTemperature))"))

                    if index < days.count - 1 {
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
            }
        }
        .padding(18)
        .contentCard(cornerRadius: 24)
    }

    // MARK: Metrics

    private func metrics(_ report: WeatherReport) -> some View {
        // Two tiles a row; one at the largest text sizes so nothing truncates.
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return LazyVGrid(columns: columns, spacing: 14) {
            WeatherMetricTile(icon: "sun.max.fill", title: "UV Index", value: report.uvIndex.formatted(), subtitle: report.uvDescription, accentColor: .yellow)

            WeatherMetricTile(icon: "wind", title: "Wind", value: settings.formatWind(kmh: report.windSpeedKmh), subtitle: String(localized: "From the \(report.windDirection)"), accentColor: .mint)

            WeatherMetricTile(icon: "humidity.fill", title: "Humidity", value: AppSettings.formatPercent(report.humidityPercent), subtitle: String(localized: "Dew point \(settings.formatTemperature(report.dewPoint))"), accentColor: .teal)

            WeatherMetricTile(
                icon: "sunrise.fill",
                title: "Sunrise",
                value: report.sunrise.map { settings.formatTime(date: $0, in: city.timeZone) } ?? "—",
                subtitle: report.sunset.map { String(localized: "Sunset \(settings.formatTime(date: $0, in: city.timeZone))") } ?? String(localized: "No sunset today"),
                accentColor: .orange
            )

            WeatherMetricTile(icon: "eye.fill", title: "Visibility", value: settings.formatDistance(km: report.visibilityKm), subtitle: visibilityDescription(report.visibilityKm), accentColor: .blue)

            WeatherMetricTile(icon: "gauge.with.dots.needle.bottom.50percent", title: "Pressure", value: settings.formatPressure(hpa: report.pressureHpa), subtitle: report.pressureTrend, accentColor: .purple)
        }
    }

    // MARK: Formatting in the city's time zone

    private func hourLabel(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour()
        style.timeZone = city.timeZone
        style.locale = settings.timeLocale
        return date.formatted(style)
    }

    private func weekdayLabel(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = city.timeZone
        return date.formatted(style)
    }

    private func visibilityDescription(_ km: Double) -> String {
        switch km {
        case 10...: String(localized: "Perfectly clear")
        case 5..<10: String(localized: "Good")
        case 1..<5: String(localized: "Hazy")
        default: String(localized: "Poor")
        }
    }
}

/// The day's low–high span placed on the 10-day scale, like the Weather app.
private struct TemperatureRangeBar: View {
    let low: Double
    let high: Double
    let overall: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let span = max(overall.upperBound - overall.lowerBound, 1)
            let start = (low - overall.lowerBound) / span
            let end = (high - overall.lowerBound) / span
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * (end - start)))
                    .offset(x: geo.size.width * start)
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

struct WeatherMetricTile: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    let subtitle: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).foregroundStyle(accentColor)
            }
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.title3, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .contentCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

/// Open-Meteo data is CC BY 4.0, so the source is credited wherever it is shown. Also says
/// how old the report is, which matters when it's the saved copy shown while offline.
private struct WeatherAttributionView: View {
    let updated: Date
    let now: Date

    var body: some View {
        VStack(spacing: 4) {
            Link(destination: URL(string: "https://open-meteo.com/")!) {
                Text("Weather data by Open‑Meteo.com")
            }
            Text("Updated \(updated.formatted(Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide).locale(.autoupdatingCurrent)))")
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .id(now)
    }
}
