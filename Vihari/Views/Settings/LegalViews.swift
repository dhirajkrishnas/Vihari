import SwiftUI

/// Addresses the legal pages link to. Kept together so the in-app text and the hosted copy agree.
enum LegalLinks {
    /// When the Privacy Policy and Terms last changed. Update it whenever their text does.
    static let policyDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 11, day: 9).date ?? .now

    static let appleStandardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let applePrivacy = URL(string: "https://www.apple.com/legal/privacy/")!
    static let openMeteo = URL(string: "https://open-meteo.com/")!
    static let openMeteoTerms = URL(string: "https://open-meteo.com/en/terms")!
    static let openMeteoLicence = URL(string: "https://open-meteo.com/en/license")!
    static let ccBy4 = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    static let appleMapsLegal = URL(string: "https://gspe21-ssl.ls.apple.com/html/attribution.html")!
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        LegalDocument(title: "Privacy Policy", updated: LegalLinks.policyDate) {
            LegalSummary(
                systemImage: "hand.raised.fill",
                title: "Vihari doesn’t collect your data.",
                message: "There’s no account, no advertising, no analytics and no tracking. Your cities and alarms stay on your devices and in your own iCloud account."
            )

            LegalSection(title: "What’s Stored and Where") {
                Text("The cities you pin, your alarms and your preferences are saved on your device. If you turn on iCloud Sync, they’re also kept in your iCloud account so your other devices can show them. They’re protected by your Apple Account and handled under Apple’s privacy policy; the developer can’t see them.")
                Text("The latest forecast for each pinned city is saved on your device, so weather appears quickly and while you’re offline. It’s replaced as new forecasts arrive and removed when you unpin the city.")
            }

            LegalSection(title: "Weather") {
                Text("To get forecasts, Vihari sends the map coordinates of each city you pin to Open‑Meteo, an open weather service, over an encrypted connection. It sends a city’s coordinates, never your location. As with any internet request, Open‑Meteo can see your device’s IP address. Open‑Meteo’s use of that information is covered by its own terms.")
                LegalLink("Open‑Meteo Terms and Privacy", destination: LegalLinks.openMeteoTerms)
            }

            LegalSection(title: "Maps and Search") {
                Text("The globe and city search use Apple Maps. Searches and the map areas being shown are sent to Apple to return results and imagery, under Apple’s privacy policy. Vihari doesn’t use or ask for your location.")
                LegalLink("Apple Privacy Policy", destination: LegalLinks.applePrivacy)
            }

            LegalSection(title: "Alarms, Siri and Shortcuts") {
                Text("Alarms are scheduled with the system on your device. When you ask Siri or run a shortcut, Vihari answers on your device using your pinned cities; Siri requests are handled by Apple.")
            }

            LegalSection(title: "Diagnostics") {
                Text("If you choose to share analytics with app developers in your device’s settings, Apple may share crash reports and usage statistics with the developer that don’t identify you. You can change this at any time in Settings.")
            }

            LegalSection(title: "Your Choices") {
                Text("You can unpin cities and delete alarms at any time. Settings > Delete All Data removes everything Vihari has stored and, with iCloud Sync on, removes it from your other devices too. Deleting the app removes the data stored on that device.")
            }

            LegalSection(title: "Children") {
                Text("Vihari is suitable for everyone and doesn’t knowingly collect personal information from anyone, including children.")
            }

            LegalSection(title: "Changes to This Policy") {
                Text("If this policy changes, the updated version will appear here and on the Vihari website, with a new date at the top.")
            }

            LegalSection(title: "Contact") {
                Text("Questions about privacy? Get in touch through the support link on Vihari’s App Store page.")
            }
        }
    }
}

// MARK: - Terms of Use

struct TermsOfUseView: View {
    var body: some View {
        LegalDocument(title: "Terms of Use", updated: LegalLinks.policyDate) {
            LegalSection(title: "Licence") {
                Text("Vihari is licensed to you under Apple’s Standard Licensed Application End User License Agreement.")
                LegalLink("Read the Licence Agreement", destination: LegalLinks.appleStandardEULA)
            }

            LegalSection(title: "Weather Information") {
                Text("Forecasts come from Open‑Meteo and are provided for general information. They can be incomplete or wrong, so don’t rely on them where safety is at stake.")
            }

            LegalSection(title: "Alarms") {
                Text("Alarms ring at the time you set in a city’s local time. They depend on your device’s settings, including its sound, Focus and permissions, so check an important alarm before you rely on it.")
            }

            LegalSection(title: "Maps") {
                Text("Maps, imagery and search results are provided by Apple and its data providers and are subject to their terms.")
                LegalLink("Apple Maps Data Providers", destination: LegalLinks.appleMapsLegal)
            }
        }
    }
}

// MARK: - Acknowledgements

struct AcknowledgementsView: View {
    var body: some View {
        LegalDocument(title: "Acknowledgements", updated: nil) {
            LegalSection(title: "Open‑Meteo") {
                Text("Weather data by Open‑Meteo.com, used under the Creative Commons Attribution 4.0 International licence (CC BY 4.0). Forecasts are derived from national weather services’ models.")
                LegalLink("Open‑Meteo.com", destination: LegalLinks.openMeteo)
                LegalLink("Open‑Meteo Licence", destination: LegalLinks.openMeteoLicence)
                LegalLink("CC BY 4.0", destination: LegalLinks.ccBy4)
            }

            LegalSection(title: "Apple Maps") {
                Text("Satellite imagery, map data and place search are provided by Apple Maps and its data providers.")
                LegalLink("Apple Maps Data Providers", destination: LegalLinks.appleMapsLegal)
            }

            LegalSection(title: "Symbols") {
                Text("Interface symbols are SF Symbols, provided by Apple.")
            }
        }
    }
}

// MARK: - Building blocks

/// A readable legal page: a large title, the date it last changed and plain sections.
private struct LegalDocument<Content: View>: View {
    let title: LocalizedStringKey
    let updated: Date?
    @ViewBuilder var content: Content

    /// iPhone, iPad and Vision Pro show the title as a large navigation title that shrinks into
    /// the bar on scroll; the Mac has no large titles, so the page shows it itself.
    private var showsTitleInPage: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showsTitleInPage || updated != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        if showsTitleInPage {
                            Text(title)
                                .font(.largeTitle.bold())
                                .accessibilityAddTraits(.isHeader)
                        }
                        if let updated {
                            Text("Updated \(updated.formatted(date: .long, time: .omitted))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                content
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
            .padding(.bottom, 20)
        }
        .background(SheetBackground())
        .textSelection(.enabled)
        .navigationTitle(title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

private struct LegalSummary: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .contentCard(cornerRadius: 22, tint: .accentColor)
        .accessibilityElement(children: .combine)
    }
}

/// An external link in a legal page: tinted (the section text around it is secondary) and
/// marked with an arrow, so it reads as a link that leaves the app.
private struct LegalLink: View {
    let title: LocalizedStringKey
    let destination: URL

    init(_ title: LocalizedStringKey, destination: URL) {
        self.title = title
        self.destination = destination
    }

    var body: some View {
        Link(destination: destination) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.tint)
    }
}

private struct LegalSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
