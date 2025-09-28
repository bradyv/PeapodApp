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
    
    private let perks = [
        (title: "Listening Stats", description: "Keep track of your listening habits.", icon: "trophy", tint: Color.purple),
        (title: "Custom App Icon", description: "A sparkly app icon, plus more to come.", icon: "app.gift", tint: Color.red),
        (title: "Jump Around", description: "Skip forward or back in custom intervals.", icon: "30.arrow.trianglehead.clockwise", tint: Color.blue),
        (title: "Playback Speed", description: "Tune playback speed to your preference.", icon: "gauge.with.dots.needle.67percent", tint: Color.accent),
        (title: "Autoplay", description: "Continue listening when the current episode ends.", icon: "sparkles.rectangle.stack", tint: Color.orange),
    ]
    
    var body: some View {
        ZStack(alignment:.bottom) {
            ScrollView {
                HStack {
                    Image(systemName: "laurel.leading")
                        .foregroundStyle(.orange)
                        .font(.system(size: 32))
                    
                    Image("peapod-mark-white")
                    
                    Image(systemName: "laurel.trailing")
                        .foregroundStyle(.orange)
                        .font(.system(size: 32))
                }
                
                Text("Peapod+")
                    .titleSerifSm()
                
                VStack(spacing: 24) {
                    Text("Support independent app development.")
                        .textBody()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    LazyVStack(spacing:2) {
                        ForEach(perks.indices, id: \.self) { index in
                            let perk = perks[index]
                            VStack(alignment:.leading) {
                                ZStack {
                                    Image(systemName: perk.icon)
                                        .font(.system(size:17))
                                        .foregroundStyle(.white)
                                }
                                .frame(width:30,height:30)
                                .background(perk.tint)
                                .clipShape(RoundedRectangle(cornerRadius:8))
                                .glassEffect(in: .rect(cornerRadius:8))
                                
                                VStack(alignment:.leading) {
                                    Text(perk.title)
                                        .foregroundStyle(.heading)
                                        .textBody()
                                    
                                    Text(perk.description)
                                        .textBody()
                                }
                            }
                            .padding()
                            .frame(maxWidth:.infinity, alignment:.leading)
                            .background(.surface)
                            .clipShape(RoundedRectangle(cornerRadius:16))
                        }
                    }
                }
                .frame(maxWidth:.infinity, alignment:.leading)
                Spacer().frame(height:150)
            }
            .contentMargins(.horizontal,16,for:.scrollContent)
            
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
            .padding()
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
//                    .mask {
//                        LinearGradient(gradient: Gradient(colors: [Color.accent.opacity(0), Color.accent]),
//                                       startPoint: .top, endPoint: .bottom)
//                    }
                .ignoresSafeArea(.all)
            }
        }
        .background(alignment:.top) {
            Image("plus-pattern")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .mask {
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                   startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea(.all)
        }
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

#Preview {
    UpgradeView()
}
