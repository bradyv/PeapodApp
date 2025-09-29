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
    
    // Define your app icons here
    let icons = [
        IconOption(name: "Default", displayName: "Default", imageName: "appicon"),
        IconOption(name: "PeapodAppIcon-Sparkly", displayName: "Sparkly", imageName: "appicon-sparkly")
    ]
    
    var body: some View {
        HStack {
            RowItem(
                icon: "app.gift",
                label: "App Icon",
                tint: Color.purple,
                framedIcon: true) {
                    appIcons
                }
        }
        .alert("Icon Changed", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeView()
                .modifier(PPSheet())
        }
    }
    
    @ViewBuilder
    var appIcons: some View {
        ForEach(icons) { icon in
            Button(action: {
                if userManager.hasPremiumAccess {
                    changeAppIcon(to: icon.name)
                } else {
                    showUpgrade = true
                }
            }) {
                ZStack(alignment:.bottomTrailing) {
                    Image(icon.imageName)
                    if (icon.name == "Default" && currentIcon == nil) || currentIcon == icon.name {
                        ZStack {
                            Image(systemName:"checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .textMini()
                        }
                        .background(Color.background)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.background, lineWidth: 1)
                        )
                    }
                }
            }
        }
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

struct IconOption: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    let imageName: String
}
