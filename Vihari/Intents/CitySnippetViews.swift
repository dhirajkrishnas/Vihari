import SwiftUI

// Siri and Shortcuts draw their own platter behind snippets and may show them in light or
// dark appearance, so these use semantic colors and no custom background.

struct CityTimeSnippetView: View {
    let cityName: String
    let localTimeFormatted: String
    let relativeDiff: String
    let dayStatus: String
    let isNight: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cityName).font(.headline)
                Text("\(dayStatus) · \(relativeDiff)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isNight ? Color.indigo : Color.orange)
            }
            Spacer(minLength: 8)
            Text(localTimeFormatted)
                .font(.system(.largeTitle, weight: .semibold))
                .monospacedDigit()
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

struct CityWeatherSnippetView: View {
    let cityName: String
    let temperature: String
    let conditionDesc: String
    let symbolName: String
    let highTemp: String
    let lowTemp: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cityName).font(.headline)
                Text(conditionDesc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("H:\(highTemp)  L:\(lowTemp)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.title)
                Text(temperature)
                    .font(.system(.largeTitle, weight: .semibold))
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

struct CityAlarmSnippetView: View {
    let cityName: String
    let alarmLabel: String
    let cityTimeFormatted: String
    let travelerTimeFormatted: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(cityName).font(.headline)
                Spacer()
                Label(alarmLabel, systemImage: "alarm.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.tangerine)
                    .lineLimit(1)
            }
            Text(cityTimeFormatted)
                .font(.system(.largeTitle, weight: .semibold))
                .monospacedDigit()
            Label(travelerTimeFormatted, systemImage: "airplane")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
