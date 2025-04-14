//
//  Peapod.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI

@main
struct Peapod: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var toastManager = ToastManager()
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    
    var appTheme: AppTheme {
       AppTheme(rawValue: appThemeRawValue) ?? .system
   }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(toastManager)
                .preferredColorScheme(preferredColorScheme(for: appTheme))
        }
    }
    
    private func preferredColorScheme(for theme: AppTheme) -> ColorScheme? {
        switch theme {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}
