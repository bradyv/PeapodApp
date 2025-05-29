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
    
    // UserDefaults keys for subscription status
    private let isSubscriberKey = "SubscriptionManager.isSubscriber"
    private let hasLifetimeAccessKey = "SubscriptionManager.hasLifetimeAccess"
    private let subscriptionPurchaseDateKey = "SubscriptionManager.subscriptionPurchaseDate"
    private let lifetimePurchaseDateKey = "SubscriptionManager.lifetimePurchaseDate"
    private let lastEntitlementCheckKey = "SubscriptionManager.lastEntitlementCheck"
    
    // Published subscription status (from UserDefaults)
    @Published var isSubscriberLocal: Bool = false
    @Published var hasLifetimeAccessLocal: Bool = false
    @Published var subscriptionPurchaseDate: Date?
    @Published var lifetimePurchaseDate: Date?
    
    // Player
    private let player = AudioPlayerManager.shared
    
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
        loadSubscriptionStatusFromUserDefaults()
        updates = observeTransactionUpdates()
    }
    
    deinit {
        updates?.cancel()
    }
    
    // MARK: - UserDefaults Management
    
    private func loadSubscriptionStatusFromUserDefaults() {
        isSubscriberLocal = UserDefaults.standard.bool(forKey: isSubscriberKey)
        hasLifetimeAccessLocal = UserDefaults.standard.bool(forKey: hasLifetimeAccessKey)
        
        if let purchaseData = UserDefaults.standard.object(forKey: subscriptionPurchaseDateKey) as? Date {
            subscriptionPurchaseDate = purchaseData
        }
        
        if let lifetimeData = UserDefaults.standard.object(forKey: lifetimePurchaseDateKey) as? Date {
            lifetimePurchaseDate = lifetimeData
        }
        
        print("📱 Loaded subscription status from UserDefaults:")
        print("   Subscriber: \(isSubscriberLocal)")
        print("   Lifetime: \(hasLifetimeAccessLocal)")
        print("   Environment: \(currentEnvironment)")
    }
    
    private func saveSubscriptionStatusToUserDefaults() {
        UserDefaults.standard.set(isSubscriberLocal, forKey: isSubscriberKey)
        UserDefaults.standard.set(hasLifetimeAccessLocal, forKey: hasLifetimeAccessKey)
        UserDefaults.standard.set(Date(), forKey: lastEntitlementCheckKey)
        
        if let date = subscriptionPurchaseDate {
            UserDefaults.standard.set(date, forKey: subscriptionPurchaseDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: subscriptionPurchaseDateKey)
        }
        
        if let date = lifetimePurchaseDate {
            UserDefaults.standard.set(date, forKey: lifetimePurchaseDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lifetimePurchaseDateKey)
        }
        
        print("💾 Saved subscription status to UserDefaults")
    }
    
    /// Clear all subscription data (useful for testing or user logout)
    func clearSubscriptionStatus() {
        isSubscriberLocal = false
        hasLifetimeAccessLocal = false
        subscriptionPurchaseDate = nil
        lifetimePurchaseDate = nil
        
        UserDefaults.standard.removeObject(forKey: isSubscriberKey)
        UserDefaults.standard.removeObject(forKey: hasLifetimeAccessKey)
        UserDefaults.standard.removeObject(forKey: subscriptionPurchaseDateKey)
        UserDefaults.standard.removeObject(forKey: lifetimePurchaseDateKey)
        UserDefaults.standard.removeObject(forKey: lastEntitlementCheckKey)
        
        print("🗑️ Cleared all subscription status")
    }
    
    // MARK: - Product Loading
    
    func loadProducts() async {
        isLoading = true
        
        do {
            let storeProducts = try await Product.products(for: allProductIDs)
            print("Loaded \(storeProducts.count) products from App Store Connect")
            
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
            
            subscriptions.sort { product1, product2 in
                guard let period1 = product1.subscription?.subscriptionPeriod,
                      let period2 = product2.subscription?.subscriptionPeriod else {
                    return false
                }
                return period1.value < period2.value
            }
            
            self.products = storeProducts
            self.subscriptionProducts = subscriptions
            self.nonConsumableProducts = nonConsumables
            self.isLoading = false
            
            print("Subscriptions: \(subscriptions.count)")
            print("Non-consumables: \(nonConsumables.count)")
            
            await updatePurchasedProducts()
            
        } catch {
            print("Failed to load products: \(error)")
            self.isLoading = false
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
            
            // Handle purchase - always set subscription status regardless of environment
            handleSuccessfulPurchase(for: product)
            
        case .userCancelled:
            print("User cancelled purchase")
            
        case .pending:
            print("Purchase is pending")
            
        @unknown default:
            break
        }
    }
    
    private func handleSuccessfulPurchase(for product: Product) {
        // Set subscription status for all environments (TestFlight and Production)
        switch product.type {
        case .autoRenewable:
            isSubscriberLocal = true
            subscriptionPurchaseDate = Date()
            print("✅ Subscription purchase completed")
            
        case .nonConsumable:
            hasLifetimeAccessLocal = true
            lifetimePurchaseDate = Date()
            print("✅ Lifetime purchase completed")
            
        default:
            break
        }
        
        saveSubscriptionStatusToUserDefaults()
    }
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }
    
    // MARK: - Subscription Status Updates
    
    func updatePurchasedProducts() async {
        var purchasedSubscriptions: [Product] = []
        var purchasedNonConsumables: [Product] = []
        
        // Check current entitlements from StoreKit
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
        
        self.purchasedSubscriptions = purchasedSubscriptions
        self.purchasedNonConsumables = purchasedNonConsumables
        
        print("Active subscriptions: \(purchasedSubscriptions.count)")
        print("Owned non-consumables: \(purchasedNonConsumables.count)")
        
        // Update local subscription status based on entitlements
        syncSubscriptionStatusWithEntitlements(
            hasSubscriptions: !purchasedSubscriptions.isEmpty,
            hasNonConsumables: !purchasedNonConsumables.isEmpty
        )
    }
    
    private func syncSubscriptionStatusWithEntitlements(hasSubscriptions: Bool, hasNonConsumables: Bool) {
        var statusChanged = false
        
        // Handle subscription status
        if hasSubscriptions && !isSubscriberLocal {
            isSubscriberLocal = true
            if subscriptionPurchaseDate == nil {
                subscriptionPurchaseDate = Date()
            }
            statusChanged = true
            print("✅ Subscription restored from entitlements")
        } else if !hasSubscriptions && isSubscriberLocal {
            isSubscriberLocal = false
            subscriptionPurchaseDate = nil
            statusChanged = true
            print("⚠️ Subscription expired - removed from local status")
            player.setBackwardInterval(30)
            player.setForwardInterval(30)
            player.setPlaybackSpeed(1.0)
        }
        
        // Handle lifetime access
        if hasNonConsumables && !hasLifetimeAccessLocal {
            hasLifetimeAccessLocal = true
            if lifetimePurchaseDate == nil {
                lifetimePurchaseDate = Date()
            }
            statusChanged = true
            print("✅ Lifetime access restored from entitlements")
        }
        
        if statusChanged {
            saveSubscriptionStatusToUserDefaults()
        }
    }
    
    // MARK: - Environment Detection
    
    private func isRunningInTestFlight() -> Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return false
        }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }
    
    private func isRunningInDebug() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    private var currentEnvironment: String {
        if isRunningInDebug() {
            return "debug"
        } else if isRunningInTestFlight() {
            return "testflight"
        } else {
            return "production"
        }
    }
    
    // MARK: - Public Status Methods
    
    /// Call this when app starts to validate subscription status
    func validateEnvironment() async {
        print("🔍 Validating subscription status...")
        await updatePurchasedProducts()
        
        // Give StoreKit time to sync if needed
        if (isSubscriberLocal || hasLifetimeAccessLocal) && purchasedSubscriptions.isEmpty && purchasedNonConsumables.isEmpty {
            print("⏳ Waiting for StoreKit sync...")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await updatePurchasedProducts()
        }
    }
    
    /// Force check subscription status and update accordingly
    func checkSubscriptionStatus() async {
        await updatePurchasedProducts()
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
    
    // MARK: - Computed Properties (StoreKit-based)
    
    var hasActiveSubscription: Bool {
        !purchasedSubscriptions.isEmpty
    }
    
    var hasLifetimeAccess: Bool {
        !purchasedNonConsumables.isEmpty
    }
    
    var hasPremiumAccess: Bool {
        hasActiveSubscription || hasLifetimeAccess
    }
    
    // MARK: - Computed Properties (UserDefaults-based)
    
    /// Whether user has premium access
    var hasPremiumAccessLocal: Bool {
        return isSubscriberLocal || hasLifetimeAccessLocal
    }
    
    /// The relevant purchase date for display
    var relevantPurchaseDate: Date? {
        return lifetimePurchaseDate ?? subscriptionPurchaseDate
    }
    
    // MARK: - Product Access
    
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
    
    // Legacy tiers for backward compatibility
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
