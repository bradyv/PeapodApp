//
//  Peapod.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import BackgroundTasks

@main
struct Peapod: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var toastManager = ToastManager()
    @StateObject private var nowPlayingManager = NowPlayingVisibilityManager()
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @AppStorage("didFlushTints") private var didFlushTints: Bool = false
    @AppStorage("hasRunOneTimeSplashMark") private var hasRunOneTimeSplashMark = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
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
                        .onAppear {
                            runDeduplicationOnceIfNeeded(context: PersistenceController.shared.container.viewContext)
                            appDelegate.scheduleEpisodeCleanup()
                            if !hasRunOneTimeSplashMark {
                                oneTimeSplashMark(context: PersistenceController.shared.container.viewContext)
                                hasRunOneTimeSplashMark = true
                            }
                            migrateMissingEpisodeGUIDs(context: PersistenceController.shared.container.viewContext)
                            mergeDuplicateEpisodes(context: PersistenceController.shared.container.viewContext)
//                            appDelegate.debugPurgeOldEpisodes() // bv debug
                        }
                } else {
                    ContentView()
                        .environmentObject(nowPlayingManager)
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(toastManager)
                        .preferredColorScheme(preferredColorScheme(for: appTheme))
                        .onAppear {
                            let context = PersistenceController.shared.container.viewContext
                            let center = UNUserNotificationCenter.current()
                                center.getNotificationSettings { settings in
                                    if settings.authorizationStatus == .notDetermined {
                                        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                                            if granted {
                                                print("✅ Local notifications authorized")
                                            } else if let error = error {
                                                print("❌ Notification permission error: \(error.localizedDescription)")
                                            } else {
                                                print("❌ Notification permission denied")
                                            }
                                        }
                                    }
                                }
                            ensureQueuePlaylistExists(context: context)
                            migrateOldQueueToPlaylist(context: context)
                            if !didFlushTints {
                                resetAllTints(in: persistenceController.container.viewContext)
                                didFlushTints = true
                            }
                        }
                        .transition(.opacity)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
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
