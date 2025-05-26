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
    
    private let baseIcons = [
        AppIcons(name: "Peapod", asset: "AppIcon-Green"),
        AppIcons(name: "Pastel", asset: "AppIcon-Pastel"),
        AppIcons(name: "Starry", asset: "AppIcon-Starry"),
        AppIcons(name: "Minty", asset: "AppIcon-Minty"),
        AppIcons(name: "Blueprint", asset: "AppIcon-Blueprint"),
        AppIcons(name: "Cupertino", asset: "AppIcon-Cupertino"),
        AppIcons(name: "Business", asset: "AppIcon-Business"),
        AppIcons(name: "Plus", asset: "AppIcon-Plus"),
    ]
    
    var availableIcons: [AppIcons] {
        var icons = baseIcons
        return icons
    }
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
