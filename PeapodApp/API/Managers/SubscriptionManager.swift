//
//  SubscriptionManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-26.
//

import Foundation
import StoreKit

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var products: [Product] = []
    @Published var subscriptionProducts: [Product] = []
    @Published var nonConsumableProducts: [Product] = []
    @Published var purchasedSubscriptions: [Product] = []
    @Published var purchasedNonConsumables: [Product] = []
    @Published var isLoading = false
    
    // Product IDs from App Store Connect
    private let subscriptionIDs: Set<String> = [
        "peapod.plus.annual",
        "peapod.plus.monthly"
    ]
    
    private let nonConsumableIDs: Set<String> = [
        "peapod.plus.lifetime"
    ]
    
    // Combined product IDs
    private var allProductIDs: Set<String> {
        subscriptionIDs.union(nonConsumableIDs)
    }
    
    private var updates: Task<Void, Never>? = nil
    
    private init() {
        // Start listening for transaction updates
        updates = observeTransactionUpdates()
    }
    
    deinit {
        updates?.cancel()
    }
    
    // MARK: - Product Loading
    
    func loadProducts() async {
        isLoading = true
        
        do {
            // Request ALL products from App Store Connect
            let storeProducts = try await Product.products(for: allProductIDs)
            print("Loaded \(storeProducts.count) products from App Store Connect")
            
            // Separate products by type
            var subscriptions: [Product] = []
            var nonConsumables: [Product] = []
            
            for product in storeProducts {
                print("Product: \(product.id), Type: \(product.type)")
                
                switch product.type {
                case .autoRenewable:
                    subscriptions.append(product)
                case .nonConsumable:
                    nonConsumables.append(product)
                default:
                    print("Unexpected product type: \(product.type)")
                }
            }
            
            // Sort subscriptions by period
            subscriptions.sort { product1, product2 in
                guard let period1 = product1.subscription?.subscriptionPeriod,
                      let period2 = product2.subscription?.subscriptionPeriod else {
                    return false
                }
                return period1.value < period2.value
            }
            
            DispatchQueue.main.async {
                self.products = storeProducts
                self.subscriptionProducts = subscriptions
                self.nonConsumableProducts = nonConsumables
                self.isLoading = false
                
                print("Subscriptions: \(subscriptions.count)")
                print("Non-consumables: \(nonConsumables.count)")
            }
            
            await updatePurchasedProducts()
            
        } catch {
            print("Failed to load products: \(error)")
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Purchase Management
    
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            UserManager.shared.updateMemberType(.subscriber)
            
        case .userCancelled:
            print("User cancelled purchase")
            
        case .pending:
            print("Purchase is pending")
            
        @unknown default:
            break
        }
    }
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }
    
    // MARK: - Subscription Status
    
    func updatePurchasedProducts() async {
        var purchasedSubscriptions: [Product] = []
        var purchasedNonConsumables: [Product] = []
        
        // Check current entitlements
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                print("Found entitlement for: \(transaction.productID)")
                
                if let product = products.first(where: { $0.id == transaction.productID }) {
                    switch product.type {
                    case .autoRenewable:
                        purchasedSubscriptions.append(product)
                        
                    case .nonConsumable:
                        purchasedNonConsumables.append(product)
                        
                    default:
                        break
                    }
                }
                
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }
        
        DispatchQueue.main.async {
            self.purchasedSubscriptions = purchasedSubscriptions
            self.purchasedNonConsumables = purchasedNonConsumables
            
            print("Active subscriptions: \(purchasedSubscriptions.count)")
            print("Owned non-consumables: \(purchasedNonConsumables.count)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [unowned self] in
            for await _ in Transaction.updates {
                await self.updatePurchasedProducts()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var hasActiveSubscription: Bool {
        !purchasedSubscriptions.isEmpty
    }
    
    var hasLifetimeAccess: Bool {
        !purchasedNonConsumables.isEmpty
    }
    
    var hasPremiumAccess: Bool {
        hasActiveSubscription || hasLifetimeAccess
    }
    
    var monthlyProduct: Product? {
        subscriptionProducts.first { product in
            product.subscription?.subscriptionPeriod.unit == .month
        }
    }
    
    var annualProduct: Product? {
        subscriptionProducts.first { product in
            product.subscription?.subscriptionPeriod.unit == .year
        }
    }
    
    var lifetimeProduct: Product? {
        nonConsumableProducts.first
    }
    
    // Legacy tiers for backward compatibility (now populated from StoreKit)
    var tiers: [SubscriptionTiers] {
        return subscriptionProducts.map { product in
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = product.priceFormatStyle.locale
            
            let price = formatter.string(from: NSDecimalNumber(decimal: product.price)) ?? ""
            let term = product.subscription?.subscriptionPeriod.unit == .month ? "Monthly" : "Annual"
            
            return SubscriptionTiers(term: term, price: price)
        }
    }
}

// MARK: - Supporting Types

struct SubscriptionTiers {
    var term: String
    var price: String
    
    init(term: String, price: String) {
        self.term = term
        self.price = price
    }
}

enum StoreError: Error {
    case failedVerification
}

// MARK: - StoreKit Extensions

extension Product.SubscriptionPeriod.Unit {
    var description: String {
        switch self {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Annual"
        @unknown default: return "Unknown"
        }
    }
}
