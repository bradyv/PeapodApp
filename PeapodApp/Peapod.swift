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
    @StateObject private var appStateManager = AppStateManager()
    @StateObject private var userManager = UserManager.shared
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Get the episodes view model from AppDelegate instead of creating a new one
    private var episodesViewModel: EpisodesViewModel {
        appDelegate.episodesViewModel
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
                .environmentObject(downloadManager)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
