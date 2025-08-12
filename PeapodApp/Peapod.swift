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
    @StateObject private var episodesViewModel = {
        let vm = EpisodesViewModel()
        vm.setup(context: PersistenceController.shared.container.viewContext)
        return vm
    }()
    @StateObject private var toastManager = ToastManager()
    @StateObject private var appStateManager = AppStateManager()
    @StateObject private var userManager = UserManager.shared
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var appTheme: AppTheme {
       AppTheme(rawValue: appThemeRawValue) ?? .system
    }
    
    init() {
        // Configure Firebase based on environment
        FirebaseConfig.configure()
        
        LogManager.shared.setupAppLifecycleLogging()
        LogManager.shared.startLogging()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStateManager)
                .environmentObject(toastManager)
                .environmentObject(userManager)
                .environmentObject(audioPlayer)
                .environmentObject(episodesViewModel)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(appTheme.colorScheme)
                .onAppear {
                    // Perform one-time setup
                    runOneTimeSetupIfNeeded()
                    
//                    EpisodeMaintenance.performMaintenance(context: viewContext)
                }
        }
    }
    
    private func runOneTimeSetupIfNeeded() {
        let context = PersistenceController.shared.container.viewContext
        
        // Run data migrations and cleanup
        runDeduplicationOnceIfNeeded(context: context)
        appDelegate.scheduleEpisodeCleanup()
    }
}
