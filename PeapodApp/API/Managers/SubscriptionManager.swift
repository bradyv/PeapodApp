//
//  SubscriptionManager.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-26.
//

import Foundation
import StoreKit

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // MARK: - Published Properties
    @Published var products: [Product] = []
    @Published var purchasedProducts: [Product] = []
    @Published var isLoading = false
    
    // Local subscription status (cached in UserDefaults)
    @Published var hasSubscription: Bool = false
    @Published var hasLifetime: Bool = false
    @Published var subscriptionPurchaseDate: Date?
    @Published var lifetimePurchaseDate: Date?
    
    // MARK: - Product IDs
    private let productIDs: Set<String> = [
        "peapod.monthly",    // Monthly subscription
        "peapod.lifetime"    // Lifetime purchase
    ]
    
    // MARK: - UserDefaults Keys
    private let hasSubscriptionKey = "hasSubscription"
    private let hasLifetimeKey = "hasLifetime"
    private let subscriptionDateKey = "subscriptionPurchaseDate"
    private let lifetimeDateKey = "lifetimePurchaseDate"
    
    private var transactionUpdates: Task<Void, Never>?
    
    // MARK: - Initialization
    private init() {
        loadCachedStatus()
        transactionUpdates = observeTransactionUpdates()
    }
    
    deinit {
        transactionUpdates?.cancel()
    }
    
    // MARK: - Computed Properties
    var hasPremiumAccess: Bool {
        hasSubscription || hasLifetime
    }
    
    var monthlyProduct: Product? {
        products.first { $0.id == "peapod.monthly" }
    }
    
    var lifetimeProduct: Product? {
        products.first { $0.id == "peapod.lifetime" }
    }
    
    var relevantPurchaseDate: Date? {
        lifetimePurchaseDate ?? subscriptionPurchaseDate
    }
    
    // MARK: - Public Methods
    
    /// Load products from App Store Connect
    func loadProducts() async {
        isLoading = true
        
        do {
            let storeProducts = try await Product.products(for: productIDs)
            
            // Sort products: monthly first, then lifetime
            let sortedProducts = storeProducts.sorted { product1, product2 in
                if product1.id == "peapod.monthly" { return true }
                if product2.id == "peapod.monthly" { return false }
                return product1.id < product2.id
            }
            
            self.products = sortedProducts
            self.isLoading = false
            
            // Update purchased products
            await updatePurchasedProducts()
            
            print("✅ Loaded \(products.count) products")
            
        } catch {
            print("❌ Failed to load products: \(error)")
            self.isLoading = false
        }
    }
    
    /// Purchase a product
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            
            // Update purchased products
            await updatePurchasedProducts()
            
            // Finish the transaction
            await transaction.finish()
            
            print("✅ Purchase completed: \(product.id)")
            
        case .userCancelled:
            print("🚫 User cancelled purchase")
            
        case .pending:
            print("⏳ Purchase is pending")
            
        @unknown default:
            break
        }
    }
    
    /// Restore purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            print("✅ Purchases restored")
        } catch {
            print("❌ Failed to restore purchases: \(error)")
        }
    }
    
    /// Check subscription status on app launch
    func checkSubscriptionStatus() async {
        await updatePurchasedProducts()
    }
    
    // MARK: - Private Methods
    
    private func loadCachedStatus() {
        hasSubscription = UserDefaults.standard.bool(forKey: hasSubscriptionKey)
        hasLifetime = UserDefaults.standard.bool(forKey: hasLifetimeKey)
        
        if let date = UserDefaults.standard.object(forKey: subscriptionDateKey) as? Date {
            subscriptionPurchaseDate = date
        }
        
        if let date = UserDefaults.standard.object(forKey: lifetimeDateKey) as? Date {
            lifetimePurchaseDate = date
        }
        
        print("📱 Loaded cached status - Subscription: \(hasSubscription), Lifetime: \(hasLifetime)")
    }
    
    private func saveCachedStatus() {
        UserDefaults.standard.set(hasSubscription, forKey: hasSubscriptionKey)
        UserDefaults.standard.set(hasLifetime, forKey: hasLifetimeKey)
        
        if let date = subscriptionPurchaseDate {
            UserDefaults.standard.set(date, forKey: subscriptionDateKey)
        }
        
        if let date = lifetimePurchaseDate {
            UserDefaults.standard.set(date, forKey: lifetimeDateKey)
        }
        
        print("💾 Saved subscription status")
    }
    
    private func updatePurchasedProducts() async {
        var activeProducts: [Product] = []
        var hasActiveSubscription = false
        var hasLifetimeAccess = false
        
        // Check current entitlements
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                if let product = products.first(where: { $0.id == transaction.productID }) {
                    activeProducts.append(product)
                    
                    if product.type == .autoRenewable {
                        hasActiveSubscription = true
                        if subscriptionPurchaseDate == nil {
                            subscriptionPurchaseDate = transaction.purchaseDate
                        }
                    } else if product.type == .nonConsumable {
                        hasLifetimeAccess = true
                        if lifetimePurchaseDate == nil {
                            lifetimePurchaseDate = transaction.purchaseDate
                        }
                    }
                }
            } catch {
                print("❌ Failed to verify transaction: \(error)")
            }
        }
        
        // Update state
        let subscriptionChanged = hasSubscription != hasActiveSubscription
        let lifetimeChanged = hasLifetime != hasLifetimeAccess
        
        self.purchasedProducts = activeProducts
        self.hasSubscription = hasActiveSubscription
        self.hasLifetime = hasLifetimeAccess
        
        // Clear subscription date if subscription expired
        if !hasActiveSubscription && subscriptionChanged {
            subscriptionPurchaseDate = nil
        }
        
        // Save to UserDefaults if anything changed
        if subscriptionChanged || lifetimeChanged {
            saveCachedStatus()
        }
        
        print("📊 Active products: \(activeProducts.count)")
        print("   Subscription: \(hasSubscription)")
        print("   Lifetime: \(hasLifetime)")
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await _ in Transaction.updates {
                await self?.updatePurchasedProducts()
            }
        }
    }
    
    // MARK: - Testing Support
    
    /// Clear all subscription data (for testing)
    func clearSubscriptionData() {
        hasSubscription = false
        hasLifetime = false
        subscriptionPurchaseDate = nil
        lifetimePurchaseDate = nil
        
        UserDefaults.standard.removeObject(forKey: hasSubscriptionKey)
        UserDefaults.standard.removeObject(forKey: hasLifetimeKey)
        UserDefaults.standard.removeObject(forKey: subscriptionDateKey)
        UserDefaults.standard.removeObject(forKey: lifetimeDateKey)
        
        print("🗑️ Cleared all subscription data")
    }
}

// MARK: - Supporting Types

enum StoreError: Error {
    case failedVerification
}

// MARK: - Product Extensions

extension Product {
    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceFormatStyle.locale
        return formatter.string(from: NSDecimalNumber(decimal: price)) ?? ""
    }
    
    var displayName: String {
        switch id {
        case "peapod.monthly":
            return "Monthly Subscription"
        case "peapod.lifetime":
            return "Lifetime Access"
        default:
            return displayName
        }
    }
}
