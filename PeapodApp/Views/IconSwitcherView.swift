//
//  IconSwitcherView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-09-29.
//

import SwiftUI

struct IconSwitcherView: View {
    @StateObject private var userManager = UserManager.shared
    @State private var currentIcon: String? = UIApplication.shared.alternateIconName
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showUpgrade = false
    @State private var showPicker = false
    
    var icons: [IconOption] {
        IconOption.availableIcons(for: userManager)
    }
    
    var body: some View {
        VStack {
            HStack(spacing: 8) {
                appIcons
                
                Text("App Icon")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textBody()
                
                    Image(systemName: "chevron.right")
                        .frame(width: 16, alignment: .trailing)
                        .textBody()
                        .opacity(0.25)
            }
            .padding(.vertical, 2)
            
            Divider()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if userManager.hasPremiumAccess {
                showPicker = true
            } else {
                showUpgrade = true
            }
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeView()
                .modifier(PPSheet())
        }
        .sheet(isPresented: $showPicker) {
            IconSheet()
                .modifier(PPSheet())
                .presentationDetents([.medium])
        }
    }
    
    @ViewBuilder
    var appIcons: some View {
        ForEach(icons.filter { icon in
            (icon.name == "Default" && currentIcon == nil) || currentIcon == icon.name
        }) { icon in
            Image(icon.imageName)
                .resizable()
                .frame(width:30,height:30)
                .clipShape(RoundedRectangle(cornerRadius:8))
                .glassEffect(in:RoundedRectangle(cornerRadius:8))
        }
    }
}

struct IconOption: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    let imageName: String
    
    @MainActor
    static func availableIcons(for userManager: UserManager) -> [IconOption] {
        let statsManager = StatisticsManager.shared
        
        var baseIcons = [
            IconOption(name: "Default", displayName: "Default", imageName: "appicon")
        ]
        
        if userManager.hasPremiumAccess {
            baseIcons.append(IconOption(name: "PeapodAppIcon-Sparkly", displayName: "Sparkly", imageName: "appicon-sparkly"))
        }
        
        if userManager.hasLifetime {
            baseIcons.append(IconOption(name: "PeapodAppIcon-Cupertino", displayName: "Cupertino", imageName: "appicon-cupertino"))
        }
        
        if userManager.hasImported {
            baseIcons.append(IconOption(name: "PeapodAppIcon-Starry", displayName: "Starry", imageName: "appicon-starry"))
        }
        
        if userManager.isBetaTester {
            baseIcons.append(IconOption(name: "PeapodAppIcon-Blueprint", displayName: "Blueprint", imageName: "appicon-blueprint"))
        }
        
        if statsManager.playCount >= 500 {
            baseIcons.append(IconOption(name: "PeapodAppIcon-Gold", displayName: "Gold", imageName: "appicon-gold"))
        }
        
        return baseIcons
    }
}

struct IconSheet: View {
    @StateObject private var userManager = UserManager.shared
    @State private var currentIcon: String? = UIApplication.shared.alternateIconName
    @State private var showAlert = false
    @State private var alertMessage = ""
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 4)
    
    var icons: [IconOption] {
        IconOption.availableIcons(for: userManager)
    }
    
    var body: some View {
        VStack {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(icons) { icon in
                    VStack {
                        Button(action: {
                            changeAppIcon(to: icon.name)
                        }) {
                            ZStack(alignment:.bottomTrailing) {
                                Image(icon.imageName)
                                    .resizable()
                                    .clipShape(RoundedRectangle(cornerRadius:23))
                                    .aspectRatio(1, contentMode:.fill)
                                    .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(Color.white.blendMode(.overlay), lineWidth: 1))
                                
                                if (icon.name == "Default" && currentIcon == nil) || currentIcon == icon.name {
                                    ZStack {
                                        Image(systemName:"checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .titleCondensed()
                                    }
                                    .background(Color.background)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.red, lineWidth: 1)
                                            .blendMode(.destinationOut)
                                    )
                                }
                            }
                            .compositingGroup()
                        }
                        Text(icon.displayName)
                            .textDetail()
                    }
                }
                
                ForEach(1...8-icons.count, id: \.self) { _ in
                    VStack {
                        ZStack {
                            RoundedRectangle(cornerRadius:23)
                                .foregroundStyle(Color.surface)
                                .aspectRatio(1, contentMode:.fill)
                            
                            Image("peapod-outline")
                                .renderingMode(.template)
                                .foregroundStyle(Color.surface)
                        }
                        
                        Text("???")
                            .textDetail()
                            .opacity(0.25)
                    }
                }
            }
        }
        .padding()
        .navigationTitle("App Icon")
    }
    
    func changeAppIcon(to iconName: String) {
        let icon = iconName == "Default" ? nil : iconName
        
        guard UIApplication.shared.supportsAlternateIcons else {
            alertMessage = "App icon switching is not supported"
            showAlert = true
            return
        }
        
        UIApplication.shared.setAlternateIconName(icon) { error in
            if let error = error {
                alertMessage = "Failed to change icon: \(error.localizedDescription)"
            } else {
                currentIcon = icon
            }
        }
    }
}
