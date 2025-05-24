//
//  FirebaseConfig.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-24.
//

import Foundation
import FirebaseCore

class FirebaseConfig {
    static func configure() {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            FirebaseApp.configure()
            print("🔥 Firebase configured with default (no bundle ID)")
            return
        }
        
        var configFileName = "GoogleService-Info"
        
        switch bundleId {
        case "com.bradyv.Peapod.Debug":
            configFileName = "GoogleService-Info-Debug"
            print("🔥 Detected DEBUG environment")
            
        case "com.bradyv.Peapod.Dev":
            configFileName = "GoogleService-Info-Dev"
            print("🔥 Detected DEV environment")
            
        default:
            print("🔥 Using default Firebase config for bundle: \(bundleId)")
        }
        
        if let path = Bundle.main.path(forResource: configFileName, ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
            print("✅ Firebase configured with \(configFileName).plist")
        } else {
            // Fallback to default
            FirebaseApp.configure()
            print("⚠️ Fallback to default Firebase config (couldn't find \(configFileName).plist)")
        }
    }
}
