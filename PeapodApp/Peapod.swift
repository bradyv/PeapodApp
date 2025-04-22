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
    @AppStorage("didFlushTints") private var didFlushTints: Bool = false
    
    var appTheme: AppTheme {
       AppTheme(rawValue: appThemeRawValue) ?? .system
   }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(toastManager)
                .preferredColorScheme(preferredColorScheme(for: appTheme))
                .onAppear {
//                    Task {
//                        await persistenceController.container.viewContext.perform {
//                            removeDuplicateEpisodes(context: persistenceController.container.viewContext)
//                            print("Episodes flushed")
//                        }
//                    }
                    if !didFlushTints {
                        resetAllTints(in: persistenceController.container.viewContext)
                        didFlushTints = true
                    }
                }
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
