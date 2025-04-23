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
    
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                } else {
                    ContentView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(toastManager)
                        .preferredColorScheme(preferredColorScheme(for: appTheme))
                        .onAppear {
                            let context = PersistenceController.shared.container.viewContext
                                ensureQueuePlaylistExists(context: context)
                                migrateOldQueueToPlaylist(context: context)
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
                        .transition(.opacity)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation {
                        showSplash = false
                    }
                }
            }
            .animation(.easeInOut(duration: 0.6), value: showSplash)
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
