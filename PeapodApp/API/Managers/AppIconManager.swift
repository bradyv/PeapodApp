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
        AppIcons(name: "Peapod", asset: "AppIcon-Green", splash: "Splash-Green"),
        AppIcons(name: "Blueprint", asset: "AppIcon-Blueprint", splash: "Splash-Blueprint"),
        AppIcons(name: "Pastel", asset: "AppIcon-Pastel", splash: "Splash-Pastel"),
        AppIcons(name: "Cupertino", asset: "AppIcon-Cupertino", splash: "Splash-Cupertino"),
        AppIcons(name: "Pride", asset: "AppIcon-Pride", splash: "Splash-Pride"),
        AppIcons(name: "Coachella", asset: "AppIcon-Coachella", splash: "Splash-Coachella"),
        AppIcons(name: "Rinzler", asset: "AppIcon-Rinzler", splash: "Splash-Rinzler"),
        AppIcons(name: "Clouds", asset: "AppIcon-Clouds", splash: "Splash-Clouds"),
    ]
    
    var availableIcons: [AppIcons] {
        var icons = baseIcons
        #if DEBUG
        icons.append(AppIcons(name: "Maze", asset: "AppIcon-Maze", splash: "Splash-Pastel"))
        #endif
        return icons
    }
    
    func splashImage(for iconAsset: String) -> String {
        return availableIcons.first(where: { $0.asset == iconAsset })?.splash ?? "Splash-Green"
    }
}

struct AppIcons {
    var name: String
    var asset: String
    var splash: String
    
    init(name: String, asset: String, splash: String) {
        self.name = name
        self.asset = asset
        self.splash = splash
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
