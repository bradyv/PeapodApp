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
    @State var xOffset: CGFloat = 0
    
    struct Perk {
        var name: String
        var label: String
        var icon: String
        
        init(name: String, label: String, icon: String) {
            self.name = name
            self.label = label
            self.icon = icon
        }
    }
    
    private var perks = [
        Perk(name: "icons", label:"Exclusive app icons", icon:"app.dashed"),
        Perk(name: "stats", label:"Advanced listening stats", icon:"rays"),
        Perk(name: "speeds", label:"Custom playback speeds", icon:"gauge.with.dots.needle.100percent"),
        Perk(name: "intervals", label:"Custom skip intervals", icon:"30.arrow.trianglehead.clockwise")
    ]
    
    var body: some View {
        VStack(spacing:16) {
            Spacer().frame(height: 24)
            
            VStack(spacing:4) {
                Image("peapod-plus-mark")
                
                Text("Peapod+")
                    .foregroundStyle(Color.white)
                    .titleSerif()
            }
            
            Text("I pour my heart into designing and building Peapod. By purchasing Peapod+, you're supporting a true independent podcast app and unlock exclusive extras.")
                .foregroundStyle(Color.white)
                .textBody()
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            InfiniteScroller(contentWidth: 208 * 4) {
                HStack(spacing:0) {
                    ForEach(perks, id: \.name) { perk in
                        Image("perk.\(perk.name)")
                    }
                }
            }
            
            Spacer()
            
//            VStack(alignment:.leading, spacing:8) {
//                ForEach(perks, id: \.name) { perk in
//                    HStack {
//                        Image(systemName:perk.icon)
//                            .foregroundStyle(Color.white)
//                            .frame(width: 24, height: 24)
//                        
//                        Text(perk.name)
//                            .foregroundStyle(Color.white)
//                            .textBody()
//                    }
//                }
//                
//                Spacer()
//            }
//            .frame(maxWidth:.infinity,alignment:.leading)
            
            VStack(spacing:16) {
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
        }
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
        HStack(spacing: 8) {
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
                .foregroundStyle(Color.white)
                .textBody()
        }
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
        ZStack(alignment:.top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(productTypeText)
                    .foregroundStyle(Color.white)
                    .titleCondensed()
                
                Text(product.displayPrice)
                    .foregroundStyle(Color.white)
                    .textBody()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.white.opacity(0.15))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .inset(by: 1)
                    .stroke(.white.opacity(isSelected ? 1 : 0.15), lineWidth: isSelected ? 2 : 1)
            )
            
            if let savings = savingsText {
                Text(savings)
                    .foregroundStyle(Color.white)
                    .textDetail()
                    .padding(.horizontal,8).padding(.vertical,4)
                    .background(Color.black)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white, lineWidth: 2))
                    .offset(y:-12)
            }
            
//            if isLifetime {
//                Text("Pay once, own forever")
//                    .textDetail()
//            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
