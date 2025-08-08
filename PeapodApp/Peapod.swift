//
//  Peapod.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import BackgroundTasks
import FirebaseCore
import FirebaseMessaging
import Kingfisher

@main
struct Peapod: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var toastManager = ToastManager()
    @StateObject private var nowPlayingManager = NowPlayingVisibilityManager()
    @StateObject private var appStateManager = AppStateManager()
    @StateObject private var userManager = UserManager.shared
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @AppStorage("didFlushTints") private var didFlushTints: Bool = false
    @AppStorage("hasRunOneTimeSplashMark") private var hasRunOneTimeSplashMark = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var appTheme: AppTheme {
       AppTheme(rawValue: appThemeRawValue) ?? .system
//        .dark
    }
    
    init() {
        // Configure Firebase based on environment
        FirebaseConfig.configure()
        
        LogManager.shared.setupAppLifecycleLogging()
        LogManager.shared.startLogging()
    }

    var body: some Scene {
        WindowGroup {
            MainContainerView()
                .environmentObject(appStateManager)
                .environmentObject(nowPlayingManager)
                .environmentObject(toastManager)
                .environmentObject(userManager)
                .environmentObject(audioPlayer)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(appTheme.colorScheme)
                .onAppear {
                    // Perform one-time setup
                    runOneTimeSetupIfNeeded()
                    
                    // Start splash sequence
                    appStateManager.startSplashSequence()
                    
                    EpisodeMaintenance.performMaintenanceIfNeeded(context: persistenceController.container.viewContext)
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
