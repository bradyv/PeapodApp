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
                            scheduleEpisodeCleanup()
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
    
    func scheduleEpisodeCleanup() {
        let identifier = "com.bradyv.Peapod.Dev.deleteOldEpisodes.v1"
        print("📆 Scheduling background task: \(identifier)")

        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 24 * 7)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Scheduled background task")
        } catch {
            print("❌ Failed to schedule background task: \(error)")
        }
    }
}
