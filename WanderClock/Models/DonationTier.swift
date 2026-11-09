import Foundation

/// The tip sizes, each a consumable In-App Purchase so people can tip more than once.
/// Their prices are set in App Store Connect per storefront; the app only ever shows those.
nonisolated enum DonationTier: String, CaseIterable, Identifiable, Sendable {
    case one = "tier1"
    case five = "tier5"
    case ten = "tier10"
    case twenty = "tier20"

    var id: String { rawValue }

    init?(productID: String) {
        guard let tier = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = tier
    }

    var productID: String {
        switch self {
        case .one: "com.dhirajkrishnasimhadri.WanderClock.donation.1"
        case .five: "com.dhirajkrishnasimhadri.WanderClock.donation.5"
        case .ten: "com.dhirajkrishnasimhadri.WanderClock.donation.10"
        case .twenty: "com.dhirajkrishnasimhadri.WanderClock.donation.20"
        }
    }

    var iconName: String {
        switch self {
        case .one: "cup.and.saucer.fill"
        case .five: "heart.fill"
        case .ten: "sparkles"
        case .twenty: "airplane.departure"
        }
    }

    var title: String {
        switch self {
        case .one: String(localized: "Coffee Tip")
        case .five: String(localized: "Generous Tip")
        case .ten: String(localized: "Super Tip")
        case .twenty: String(localized: "World Supporter")
        }
    }

    var subtitle: String {
        switch self {
        case .one: String(localized: "A warm token of appreciation")
        case .five: String(localized: "Helps fuel ongoing updates and polish")
        case .ten: String(localized: "Supports independent app development")
        case .twenty: String(localized: "Champions future features and design")
        }
    }
}
