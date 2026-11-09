import Foundation
import Observation
import StoreKit
import SwiftUI
import os

/// Voluntary tips, sold as consumable In-App Purchases with StoreKit 2.
///
/// Prices always come from the App Store, in the person's own storefront and currency. Until
/// they've loaded, the tip buttons wait rather than show a guessed price.
@Observable
final class DonationStore {
    static let shared = DonationStore()

    private(set) var products: [DonationTier: Product] = [:]
    private(set) var isLoading = false
    /// True when the App Store couldn't be reached the last time products were requested.
    private(set) var loadFailed = false
    private(set) var purchasingTier: DonationTier?
    private(set) var hasDonatedSuccessfully = false
    var errorMessage: String?

    @ObservationIgnored private var transactionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.dhirajkrishnasimhadri.WanderClock", category: "Donations")

    private init() {
        transactionTasks = [
            // A tip interrupted before it finished (the app quit, Ask to Buy) is completed now.
            Task { [weak self] in
                for await result in StoreKit.Transaction.unfinished { await self?.handle(result) }
            },
            Task { [weak self] in
                for await result in StoreKit.Transaction.updates { await self?.handle(result) }
            }
        ]
        Task { await loadProducts() }
    }

    /// The tier's price in the person's storefront, or nil until the App Store has answered.
    func displayPrice(for tier: DonationTier) -> String? {
        products[tier]?.displayPrice
    }

    /// Fetches the tip products from the App Store (or the StoreKit configuration while testing).
    func loadProducts() async {
        guard !isLoading, products.count < DonationTier.allCases.count else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await Product.products(for: DonationTier.allCases.map(\.productID))
            products = Dictionary(uniqueKeysWithValues: fetched.compactMap { product in
                DonationTier(productID: product.id).map { ($0, product) }
            })
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
            log.error("Couldn't load tip products: \(error.localizedDescription)")
        }
    }

    /// Buys a tip with SwiftUI's purchase action, which shows the App Store sheet in the right window.
    func purchase(_ tier: DonationTier, using purchase: PurchaseAction) async {
        guard purchasingTier == nil, let product = products[tier] else { return }
        purchasingTier = tier
        defer { purchasingTier = nil }

        do {
            switch try await purchase(product) {
            case .success(let verification):
                await handle(verification)
                if case .unverified = verification {
                    errorMessage = String(localized: "The App Store couldn’t verify this purchase. Please try again later.")
                }
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            log.error("Tip purchase failed for \(tier.productID): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Finishes a verified tip and says thank you. Tips unlock nothing, so there's nothing else to deliver.
    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else {
            log.error("Ignored an unverified tip transaction.")
            return
        }
        await transaction.finish()
        guard transaction.revocationDate == nil, DonationTier(productID: transaction.productID) != nil else { return }
        hasDonatedSuccessfully = true
    }
}
