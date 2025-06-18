//
//  AppIconManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-23.
//

import Foundation

class AppIconManager: ObservableObject {
    static let shared = AppIconManager()
    
    private init() {}
    
    let baseIcons = [
        AppIcons(name: "Peapod", asset: "AppIcon-Green"),
        AppIcons(name: "Colourful", asset: "AppIcon-Colourful"),
        AppIcons(name: "Wave", asset: "AppIcon-Wave"),
        AppIcons(name: "Cupertino", asset: "AppIcon-Cupertino"),
        AppIcons(name: "Sunset", asset: "AppIcon-Sunset"),
        AppIcons(name: "Strawberry", asset: "AppIcon-Strawberry"),
        AppIcons(name: "Blueprint", asset: "AppIcon-Blueprint")
    ]
    
    let prideIcons = [
        AppIcons(name: "lgbtq", asset: "AppIcon-lgbtq"),
        AppIcons(name: "Trans", asset: "AppIcon-Trans"),
        AppIcons(name: "Lesbian", asset: "AppIcon-Lesbian"),
        AppIcons(name: "NonBinary", asset: "AppIcon-NonBinary"),
        AppIcons(name: "Bi", asset: "AppIcon-Bi"),
    ]
    
    let legacyIcons = [
        AppIcons(name: "LegacyPeapod", asset:"AppIcon-Legacy-PP"),
        AppIcons(name: "LegacyCupertino", asset:"AppIcon-Legacy-Apple"),
        AppIcons(name: "LegacyPastel", asset:"AppIcon-Legacy-SoftColor"),
        AppIcons(name: "LegacyPride", asset:"AppIcon-Legacy-Pride"),
        AppIcons(name: "LegacyRinzler", asset:"AppIcon-Legacy-Rinzler"),
        AppIcons(name: "LegacyCoachella", asset:"AppIcon-Legacy-Coachella"),
        AppIcons(name: "LegacyClouds", asset:"AppIcon-Legacy-Clouds"),
    ]
    
    let mkiIcons = [
        AppIcons(name:"MkI", asset:"AppIcon-MkI-Peapod"),
    ]
    
//    var availableIcons: [AppIcons] {
//        var icons = baseIcons + legacyIcons + mkiIcons
//        return icons
//    }
}

struct AppIcons {
    var name: String
    var asset: String
    
    init(name: String, asset: String) {
        self.name = name
        self.asset = asset
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "circle.righthalf.filled.inverse"
        case .dark: return "moon.stars.fill"
        case .light: return "sun.max"
        }
    }
}
