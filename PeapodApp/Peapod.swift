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
    @StateObject private var appStateManager = AppStateManager()
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @AppStorage("didFlushTints") private var didFlushTints: Bool = false
    @AppStorage("hasRunOneTimeSplashMark") private var hasRunOneTimeSplashMark = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var appTheme: AppTheme {
       AppTheme(rawValue: appThemeRawValue) ?? .system
    }
    
    init() {
        #if !DEBUG
        LogManager.shared.setupAppLifecycleLogging()
        LogManager.shared.startLogging()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainContainerView()
                .environmentObject(appStateManager)
                .environmentObject(nowPlayingManager)
                .environmentObject(toastManager)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(preferredColorScheme(for: appTheme))
                .onAppear {
                    // Perform one-time setup
                    runOneTimeSetupIfNeeded()
                    
                    // Start splash sequence
                    appStateManager.startSplashSequence()
                }
        }
    }
    
    private func runOneTimeSetupIfNeeded() {
        let context = PersistenceController.shared.container.viewContext
        
        // Run data migrations and cleanup
        runDeduplicationOnceIfNeeded(context: context)
        appDelegate.scheduleEpisodeCleanup()
        if !hasRunOneTimeSplashMark {
            oneTimeSplashMark(context: context)
            hasRunOneTimeSplashMark = true
        }
        migrateMissingEpisodeGUIDs(context: context)
        
        // Setup queues and other required data
        ensureQueuePlaylistExists(context: context)
        migrateOldQueueToPlaylist(context: context)
        if !didFlushTints {
            resetAllTints(in: context)
            didFlushTints = true
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
