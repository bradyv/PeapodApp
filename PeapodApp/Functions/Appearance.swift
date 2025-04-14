//
//  Appearance.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-14.
//

import Foundation

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match System"
        case .dark: return "Dark Mode"
        case .light: return "Light Mode"
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "sparkles"
        case .dark: return "moon.stars"
        case .light: return "sun.max"
        }
    }
}
