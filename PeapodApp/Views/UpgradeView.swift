//
//  UpgradeView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-26.
//

import SwiftUI
import StoreKit

struct UpgradeView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var userManager = UserManager.shared
    @State private var isPurchasing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            VStack(alignment:.leading, spacing: 24) {
                Text("Purchasing a subscription unlocks **listening stats**, custom **skip intervals**, custom **playback speed**, and my eternal gratitude.")
                        .textBody()
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal)
                
                Spacer()
                
                InfiniteScroller(contentWidth: 208 * 3) {
                    HStack(spacing:0) {
                        Image("perk-stats")
                        Image("perk-speed")
                        Image("perk-intervals")
                    }
                }
                
                Spacer()
                
                VStack(spacing:12) {
                    // Purchase Options
                    if !userManager.hasPremiumAccess {
                        HStack(spacing: 16) {
                            // Monthly Subscription
                            if let monthlyProduct = subscriptionManager.monthlyProduct {
                                PurchaseButton(
                                    title: "Monthly",
                                    subtitle: "\(monthlyProduct.formattedPrice)/mo",
                                    product: monthlyProduct,
                                    isPurchasing: $isPurchasing,
                                    onPurchaseComplete: {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            dismiss()
                                        }
                                    }
                                )
                            }
                            
                            // Lifetime Purchase
                            if let lifetimeProduct = subscriptionManager.lifetimeProduct {
                                PurchaseButton(
                                    title: "Lifetime",
                                    subtitle: "\(lifetimeProduct.formattedPrice)",
                                    product: lifetimeProduct,
                                    isPurchasing: $isPurchasing,
                                    onPurchaseComplete: {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            dismiss()
                                        }
                                    }
                                )
                            }
                        }
                    }
                    
                    // Footer Actions
                    HStack(spacing: 12) {
                        Button("Privacy Policy") {
                            if let url = URL(string: "https://peapod.fm/privacy") {
                                openURL(url)
                            }
                        }
                        .textDetail()
                        
                        Button("Terms of Use") {
                            if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                                openURL(url)
                            }
                        }
                        .textDetail()
                    }
                }
                .padding(.horizontal)
            }
            .background(Color.background)
            .frame(maxWidth:.infinity, alignment:.leading)
            .navigationTitle("Peapod+")
            .disabled(isPurchasing)
            .toolbar {
                ToolbarItem(placement:.primaryAction) {
                    Button("Restore Purchases") {
                        Task {
                            await subscriptionManager.restorePurchases()
                            if userManager.hasPremiumAccess {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await subscriptionManager.loadProducts()
        }
        .alert("Purchase Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
}

struct PurchaseButton: View {
    let title: String
    let subtitle: String
    let product: Product
    @Binding var isPurchasing: Bool
    var isRecommended: Bool = false
    let onPurchaseComplete: (() -> Void)?
    
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(title: String, subtitle: String, product: Product, isPurchasing: Binding<Bool>, isRecommended: Bool = false, onPurchaseComplete: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.product = product
        self._isPurchasing = isPurchasing
        self.isRecommended = isRecommended
        self.onPurchaseComplete = onPurchaseComplete
    }
    
    var body: some View {
        Button {
            purchaseProduct()
        } label: {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .titleCondensed()
                        
                        Text(subtitle)
                            .textDetail()
                    }
                    
                    Spacer()
                    
                    if isPurchasing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isRecommended ? Color.heading : Color.surface, lineWidth: isRecommended ? 2 : 1)
            )
        }
        .disabled(isPurchasing)
        .alert("Purchase Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func purchaseProduct() {
        isPurchasing = true
        
        Task {
            do {
                try await subscriptionManager.purchase(product)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            
            await MainActor.run {
                isPurchasing = false
                onPurchaseComplete?()
            }
        }
    }
}
