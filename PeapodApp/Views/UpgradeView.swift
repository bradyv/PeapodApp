//
//  UpgradeView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-26.
//

import SwiftUI

struct UpgradeView: View {
    private var tiers = SubscriptionManager.shared.tiers
    @State private var selectedTier: String = ""
    
    var body: some View {
        VStack {
            Spacer().frame(height:24)
            
            Image("peapod-plus-mark")
            
            Text("Join Peapod+")
                .titleSerif()
            
            Text("Support the ongoing development of an independent podcast app. You’ll get custom app icons, more listening insights, and my eternal gratitude.")
                .textBody()
                .multilineTextAlignment(.center)
            
            HStack {
                ForEach(tiers, id: \.term) { tier in
                    let isSelected = selectedTier == tier.term

                    VStack(alignment:.leading, spacing: 8) {
                        Text(tier.term)
                            .titleCondensed()
                        
                        Text(tier.price)
                            .textBody()
                    }
                    .frame(maxWidth:.infinity, alignment:.leading)
                    .padding()
                    .background(
                        LinearGradient(
                            stops: [
                                Gradient.Stop(color: .white.opacity(0.3), location: 0.00),
                                Gradient.Stop(color: .white.opacity(0), location: 1.00),
                            ],
                            startPoint: UnitPoint(x: 0, y: 0),
                            endPoint: UnitPoint(x: 0.5, y: 1)
                        )
                    )
                    .background(.white.opacity(0.15))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .inset(by: 1)
                            .stroke(isSelected ? Color.heading : .white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                    )
                    .onTapGesture {
                        selectedTier = tier.term
                    }
                }
            }
            
            Button(action: {
                //
            }) {
                Text("Become a Supporter")
                    .frame(maxWidth:.infinity)
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
            
            Button(action: {
                //
            }) {
                Text("Restore purchases")
                    .textBody()
            }
            .foregroundStyle(Color.white)
        }
        .padding(.horizontal)
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.top)
        .background {
            GeometryReader { geometry in
                Color(hex: "#C9C9C9")
                Image("pro-pattern")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .ignoresSafeArea(.all)
        }
        .onAppear {
            // Select the first tier by default
            if selectedTier.isEmpty && !tiers.isEmpty {
                selectedTier = tiers[0].term
            }
        }
    }
}

#Preview {
    UpgradeView()
}
