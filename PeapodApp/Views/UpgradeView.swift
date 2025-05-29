//
//  UpgradeView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-26.
//

import SwiftUI
import StoreKit

struct UpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack {
            Spacer().frame(height: 24)
            
            Image("peapod-plus-mark")
            
            Text("I pour my heart into designing and building Peapod. By purchasing Peapod+, you'll support a true independent podcast app and unlock exclusive extras.")
                .textBody()
                .multilineTextAlignment(.leading)
            
            if subscriptionManager.isLoading {
                ProgressView("Loading subscriptions...")
                    .padding()
            } else {
                subscriptionOptionsView
            }
            
            purchaseButton
            
            restoreButton
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            backgroundView
        }
        .task {
            await subscriptionManager.loadProducts()
            selectDefaultProduct()
        }
        .onChange(of: subscriptionManager.subscriptionProducts) { _, _ in
            // Auto-select when products finish loading
            if selectedProduct == nil {
                selectDefaultProduct()
            }
        }
        .alert("Purchase Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var subscriptionOptionsView: some View {
        VStack(spacing: 16) {
            // Subscription products
            if !subscriptionManager.subscriptionProducts.isEmpty {
                
                ForEach(subscriptionManager.subscriptionProducts, id: \.id) { product in
                    ProductCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id
                    ) {
                        selectedProduct = product
                    }
                }
            }
            
            // Non-consumable products (like lifetime purchase)
            if !subscriptionManager.nonConsumableProducts.isEmpty {
                
                ForEach(subscriptionManager.nonConsumableProducts, id: \.id) { product in
                    ProductCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id,
                        isLifetime: true
                    ) {
                        selectedProduct = product
                    }
                }
            }
        }
    }
    
    private var purchaseButton: some View {
        Button(action: {
            Task {
                await purchaseSelectedProduct()
            }
        }) {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                
                Text(isPurchasing ? "Processing..." : "Subscribe")
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#3CA4F4") ?? .blue,
                        Color(hex: "#9D93C5") ?? .purple,
                        Color(hex: "#E98D64") ?? .orange
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .buttonStyle(ShadowButton())
        .disabled(isPurchasing)
        .opacity(isPurchasing ? 0.6 : 1.0)
    }
    
    private var restoreButton: some View {
        Button(action: {
            Task {
                await subscriptionManager.restorePurchases()
            }
        }) {
            Text("Restore purchases")
                .textBody()
        }
        .foregroundStyle(Color.white)
        .disabled(isPurchasing)
    }
    
    private var backgroundView: some View {
        GeometryReader { geometry in
            Color(hex: "#C9C9C9")
            Image("pro-pattern")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea(.all)
    }
    
    private func purchaseSelectedProduct() async {
        guard let product = selectedProduct else { return }
        
        isPurchasing = true
        
        do {
            try await subscriptionManager.purchase(product)
            // Purchase successful - dismiss the sheet
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isPurchasing = false
    }
    
    private func selectDefaultProduct() {
        // Select annual subscription first (usually the best value)
        if let annualProduct = subscriptionManager.annualProduct {
            selectedProduct = annualProduct
        } else if let firstSubscription = subscriptionManager.subscriptionProducts.first {
            selectedProduct = firstSubscription
        } else if let firstProduct = subscriptionManager.nonConsumableProducts.first {
            selectedProduct = firstProduct
        }
    }
}

struct ProductCard: View {
    let product: Product
    let isSelected: Bool
    let isLifetime: Bool
    let onTap: () -> Void
    
    init(product: Product, isSelected: Bool, isLifetime: Bool = false, onTap: @escaping () -> Void) {
        self.product = product
        self.isSelected = isSelected
        self.isLifetime = isLifetime
        self.onTap = onTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(productTypeText)
                .titleCondensed()
            
            Text(product.displayPrice)
                .textBody()
            
            if let savings = savingsText {
                Text(savings)
                    .textDetail()
                    .padding()
                    .background(Color.black)
                    .clipShape(Capsule())
            }
            
//            if isLifetime {
//                Text("Pay once, own forever")
//                    .textDetail()
//            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                stops: [
                    Gradient.Stop(color: .white.opacity(isSelected ? 0.4 : 0.3), location: 0.00),
                    Gradient.Stop(color: .white.opacity(0), location: 1.00),
                ],
                startPoint: UnitPoint(x: 0, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 1)
            )
        )
        .background(.white.opacity(isSelected ? 0.25 : 0.15))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .inset(by: 1)
                .stroke(.white.opacity(isSelected ? 0.3 : 0.15), lineWidth: isSelected ? 2 : 1)
        )
        .onTapGesture {
            onTap()
        }
    }
    
    private var productTypeText: String {
        if isLifetime {
            return "Lifetime"
        }
        
        guard let subscription = product.subscription else { return "Unknown" }
        
        switch subscription.subscriptionPeriod.unit {
        case .month:
            return "Monthly"
        case .year:
            return "Annual"
        default:
            return subscription.subscriptionPeriod.unit.description
        }
    }
    
    private var savingsText: String? {
        // Calculate savings for annual subscription
        guard let subscription = product.subscription,
              subscription.subscriptionPeriod.unit == .year else {
            return nil
        }
        
        // This is a simplified calculation - you'd want to compare with the monthly price
        return "Save 25%" // Replace with actual calculation
    }
}

#Preview {
    UpgradeView()
}
