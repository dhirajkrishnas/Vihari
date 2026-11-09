import SwiftUI

enum DetailTab: Int, CaseIterable, Identifiable {
    case weather, alarms

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .weather: "Weather"
        case .alarms: "Alarms"
        }
    }
}

struct CityDetailView: View {
    let city: PinnedCity
    let weather: WeatherState
    let alarms: [CityAlarm]
    let onClose: () -> Void
    let onSetAlarmEnabled: (CityAlarm, Bool) -> Void
    let onDeleteAlarm: (CityAlarm) -> Void
    let onSaveAlarm: (CityAlarm) -> Void
    let onRetryWeather: () -> Void
    /// False where the detail sits in a sheet or panel that brings its own glass.
    var showsBackground = true

    @State private var selectedTab: DetailTab
    @State private var settings = AppSettings.shared

    init(
        city: PinnedCity,
        weather: WeatherState,
        alarms: [CityAlarm],
        initialTab: DetailTab = .weather,
        showsBackground: Bool = true,
        onClose: @escaping () -> Void,
        onSetAlarmEnabled: @escaping (CityAlarm, Bool) -> Void,
        onDeleteAlarm: @escaping (CityAlarm) -> Void,
        onSaveAlarm: @escaping (CityAlarm) -> Void,
        onRetryWeather: @escaping () -> Void
    ) {
        self.city = city
        self.weather = weather
        self.alarms = alarms
        self.onClose = onClose
        self.onSetAlarmEnabled = onSetAlarmEnabled
        self.onDeleteAlarm = onDeleteAlarm
        self.onSaveAlarm = onSaveAlarm
        self.onRetryWeather = onRetryWeather
        self.showsBackground = showsBackground
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Picker("Section", selection: $selectedTab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .sensoryFeedback(.selection, trigger: selectedTab)

            pages
        }
        .background {
            // The glass runs under the home indicator while the content stays inside the safe area.
            if showsBackground {
                Color.clear
                    .floatingGlass(cornerRadius: 34)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    /// Swipeable pages on iPhone, iPad and Vision Pro. The Mac has no page style (a tab view
    /// there would add a second tab bar under the segmented control), so it switches directly.
    ///
    /// The pages are a paging scroll view rather than a page-style tab view: beside a side pane the
    /// detail slides in from the side, and a page-style tab view that moves sideways as it appears
    /// lays its pages out at the wrong width, leaving the page off-centre with the next one showing.
    @ViewBuilder
    private var pages: some View {
        #if os(macOS)
        Group {
            switch selectedTab {
            case .weather: weatherPage
            case .alarms: alarmsPage
            }
        }
        .transition(.opacity)
        .animation(.smooth, value: selectedTab)
        #else
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                weatherPage
                    .containerRelativeFrame(.horizontal)
                    .id(DetailTab.weather)
                alarmsPage
                    .containerRelativeFrame(.horizontal)
                    .id(DetailTab.alarms)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: visiblePage)
        // The scroll position doesn't set where the pages start, so they start at the tab's page here.
        .defaultScrollAnchor(firstPageAnchor, for: .initialOffset)
        .animation(.smooth, value: selectedTab)
        #endif
    }

    /// The page in view: swiping to a page selects its tab, and choosing a tab scrolls to its page.
    private var visiblePage: Binding<DetailTab?> {
        Binding(get: { selectedTab }, set: { if let tab = $0 { selectedTab = tab } })
    }

    /// The selected tab's page, as a point across the row of pages (0 the first, 1 the last).
    private var firstPageAnchor: UnitPoint {
        UnitPoint(x: Double(selectedTab.rawValue) / Double(max(1, DetailTab.allCases.count - 1)), y: 0.5)
    }

    private var weatherPage: some View {
        CityWeatherPageView(city: city, weather: weather, onRetry: onRetryWeather)
    }

    private var alarmsPage: some View {
        CityAlarmsPageView(
            city: city,
            alarms: alarms,
            onSetEnabled: onSetAlarmEnabled,
            onDeleteAlarm: onDeleteAlarm,
            onSaveAlarm: onSaveAlarm,
            onFinishOnboarding: onClose
        )
    }

    /// The city's local time and how it compares to here. Its name is in the bar above, beside Back.
    private var header: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.formatTime(date: context.date, in: city.timeZone))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(city.dayDifferenceStatus(date: context.date)), \(city.relativeTimeDifference(date: context.date))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(city.name), \(settings.formatTime(date: context.date, in: city.timeZone)), \(city.relativeTimeDescription(date: context.date))"))
            .accessibilityAddTraits(.isHeader)
        }
    }
}
