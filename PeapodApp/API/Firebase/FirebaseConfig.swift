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
        
        var configFileName = "GoogleService-Info-Release"
        
        switch bundleId {
        case "com.bradyv.Peapod.Debug":
            configFileName = "GoogleService-Info-Debug"
            print("🔥 Detected DEBUG environment")
            
        case "com.bradyv.Peapod.Dev":
            configFileName = "GoogleService-Info-Release"
            print("🔥 Detected DEV environment")
            
        default:
            configFileName = "GoogleService-Info-Release" // Explicit default
            print("🔥 Using default Firebase config for bundle: \(bundleId)")
        }
        
        print("🔍 Looking for config file: \(configFileName).plist")
        
        if let path = Bundle.main.path(forResource: configFileName, ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
            print("✅ Firebase configured with \(configFileName).plist")
            print("✅ Project ID: \(options.projectID ?? "unknown")")
        } else {
            print("❌ Could not find \(configFileName).plist in bundle")
            print("📁 Available plist files in bundle:")
            Bundle.main.paths(forResourcesOfType: "plist", inDirectory: nil).forEach { path in
                print("   - \(URL(fileURLWithPath: path).lastPathComponent)")
            }
            
            // Fallback to default
            FirebaseApp.configure()
            print("⚠️ Fallback to default Firebase config")
        }
    }
}
