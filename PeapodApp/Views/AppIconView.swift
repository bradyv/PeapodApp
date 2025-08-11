//
//  AppIconView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-22.
//


import SwiftUI

struct AppIconView: View {
    @ObservedObject private var userManager = UserManager.shared
    @Binding var selectedIconName: String
    @State private var showingUpgrade = false
    
    private var iconCategories: [(String, [AppIcons])] {
        return [
            ("Peapod", AppIconManager.shared.baseIcons),
            ("Pride", AppIconManager.shared.prideIcons),
            ("Legacy", AppIconManager.shared.legacyIcons),
            ("MKI", AppIconManager.shared.mkiIcons)
        ]
    }
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 4)
    
    // Add this computed property to determine if an icon is available
    private func isIconAvailable(_ icon: AppIcons) -> Bool {
        let freeIcons = ["Peapod", "lgbtq", "Trans", "Lesbian", "Bi", "NonBinary", "LegacyPride"]
        return userManager.isSubscriber || freeIcons.contains(icon.name)
    }
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:24)
            
            Text("App Icon")
                .titleSerif()
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(.top,24)
            
            Spacer().frame(height:24)
            
            if !userManager.isSubscriber {
                VStack {
                    Image("peapod-plus-mark")
                    
                    VStack(spacing: 4) {
                        Text("Support an independent podcast app.")
                            .foregroundStyle(Color.white)
                            .textBody()
                        
                        Text("Unlock all app icons.")
                            .foregroundStyle(Color.white)
                            .textBody()
                    }
                }
                .frame(maxWidth:.infinity)
                .foregroundStyle(Color.white)
                .padding()
                .background {
                    GeometryReader { geometry in
                        Image("pro-pattern")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                    .ignoresSafeArea(.all)
                }
                .clipShape(RoundedRectangle(cornerRadius:16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
                .onTapGesture {
                    showingUpgrade = true
                }
                Spacer().frame(height:24)
            }
            
            ForEach(iconCategories, id: \.0) { categoryName, icons in
                Text("\(categoryName)")
                    .headerSection()
                    .frame(maxWidth:.infinity,alignment:.leading)
                
                LazyVGrid(columns: columns) {
                    ForEach(icons, id: \.name) { icon in
                        IconButton(
                            icon: icon,
                            isSelected: selectedIconName == icon.asset,
                            isAvailable: isIconAvailable(icon),
                            onTap: { handleIconTap(icon) }
                        )
                    }
                }
                .padding()
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius:16))
                
                Spacer().frame(height: 24)
            }
        }
        .frame(maxHeight:.infinity, alignment:.topLeading)
        .contentMargins(16, for: .scrollContent)
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView()
                .modifier(PPSheet())
        }
    }
    
    private func handleIconTap(_ icon: AppIcons) {
        if isIconAvailable(icon) {
            UIApplication.shared.setAlternateIconName(icon.asset == "AppIcon-Green" ? nil : icon.asset) { error in
                if let error = error {
                    LogManager.shared.error("❌ Failed to switch icon: \(error)")
                } else {
                    LogManager.shared.info("✅ Icon switched to \(icon.name)")
                    withAnimation(.easeInOut(duration: 0.5)) {
                        selectedIconName = icon.asset
                    }
                }
            }
        } else {
            showingUpgrade = true
        }
    }
}

struct IconButton: View {
    let icon: AppIcons
    let isSelected: Bool
    let isAvailable: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack {
                ZStack(alignment:.bottomTrailing) {
                    Image(icon.name)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .opacity(isAvailable ? 1 : 0.5)
                        .background {
                            if isSelected {
                                // Create gap effect with background
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.heading)
                                    .frame(width: 72, height: 72) // 4pt larger on each side
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color.background)
                                            .frame(width: 68, height: 68) // 2pt gap
                                    )
                            }
                        }
                    if !isAvailable {
                        VStack {
                            Image(systemName: "lock.circle.fill")
                                .foregroundStyle(Color.heading)
                        }
                        .padding(1)
                        .background(Color.background)
                        .clipShape(Circle())
                        .offset(x:4,y:4)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
