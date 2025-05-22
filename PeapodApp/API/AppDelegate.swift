//
//  AppDelegate.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-24.
//

import UIKit
import BackgroundTasks
import CoreData
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var pendingNotificationEpisodeID: String?
    
    override init() {
        super.init()
        print("🧬 AppDelegate initialized")
        UNUserNotificationCenter.current().delegate = self
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Enable remote control events when app becomes active
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        // Make AppDelegate the first responder
        self.becomeFirstResponder()
    }

    // Now these overrides will work
    override func remoteControlReceived(with event: UIEvent?) {
        print("🎛️ AppDelegate received remote control event")
        AudioPlayerManager.shared.remoteControlReceived(with: event)
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        setupCurrentUser(context: PersistenceController.shared.container.viewContext)

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.bradyv.Peapod.Dev.deleteOldEpisodes.v1", using: nil) { task in
            print("🚀 BGTask fired: com.bradyv.Peapod.Dev.deleteOldEpisodes.v1")
            self.handleOldEpisodeCleanup(task: task as! BGAppRefreshTask)
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.bradyv.Peapod.Dev.refreshEpisodes.v1", using: nil) { task in
            print("🚀 BGTask fired: com.bradyv.Peapod.Dev.refreshEpisodes.v1")
            self.handleEpisodeRefresh(task: task as! BGAppRefreshTask)
        }
        
        scheduleEpisodeRefresh()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                for request in requests {
                    print("📋 Pending BGTask:", request.identifier)
                }
            }
        }
        return true
    }

    // 🧩 When user taps a notification
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let episodeID = userInfo["episodeID"] as? String {
            // Store the episode ID for cold start scenarios
            AppDelegate.pendingNotificationEpisodeID = episodeID
            // Also post notification for immediate handling if app is already running
            NotificationCenter.default.post(name: .didTapEpisodeNotification, object: episodeID)
        }
        completionHandler()
    }
    
    func debugPurgeOldEpisodes() {
        let context = PersistenceController.shared.container.viewContext

        context.perform {
            print("🧪 DEBUG: Starting old episode purge")

            let request: NSFetchRequest<Episode> = Episode.fetchRequest()
            request.predicate = NSPredicate(format: "(podcast == nil OR podcast.isSubscribed == NO) AND isSaved == NO AND isPlayed == NO")

            do {
                let episodes = try context.fetch(request)
                print("→ Found \(episodes.count) episode(s) eligible for deletion")

                for episode in episodes {
                    let title = episode.title ?? "Untitled"
                    let podcast = episode.podcast?.title ?? "nil"
                    print("   - Deleting: \(title) from \(podcast)")
                    context.delete(episode)
                }

                try context.save()
                print("✅ DEBUG: Deleted \(episodes.count) episode(s)")
            } catch {
                print("❌ DEBUG purge failed: \(error)")
            }
        }
    }

    private func handleOldEpisodeCleanup(task: BGAppRefreshTask) {
        scheduleEpisodeCleanup() // Reschedule for next week

        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "(podcast = nil OR podcast.isSubscribed != YES) AND isSaved == NO AND isPlayed == NO")

            do {
                let results = try context.fetch(fetchRequest)
                for episode in results {
                    context.delete(episode)
                }
                try context.save()
            } catch {
                print("Background cleanup failed: \(error)")
            }

            task.setTaskCompleted(success: true)
        }
    }

    func scheduleEpisodeCleanup() {
        let request = BGAppRefreshTaskRequest(identifier: "com.bradyv.Peapod.Dev.deleteOldEpisodes.v1")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 24 * 7) // 1 week

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule episode cleanup task: \(error)")
        }
    }
    
    private func handleEpisodeRefresh(task: BGAppRefreshTask) {
        let context = PersistenceController.shared.container.newBackgroundContext()

        context.perform {
            EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                task.setTaskCompleted(success: true)
                self.scheduleEpisodeRefresh() // Reschedule after completing
            }
        }
    }
    
    func scheduleEpisodeRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.bradyv.Peapod.Dev.refreshEpisodes.v1")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Scheduled background episode refresh")
            print("⏲️ Next episode refresh: \(request.earliestBeginDate!)")
        } catch {
            print("❌ Could not schedule background episode refresh: \(error)")
        }
    }
    
    func checkAndSetUserSince(for user: User, context: NSManagedObjectContext) {
        // Check if userSince is nil
        if user.userSince == nil {
            // Set to current date
            user.userSince = Date()
            
            // Save the context
            do {
                try context.save()
                print("User since date set to: \(user.userSince!)")
            } catch {
                print("Failed to save user since date: \(error)")
            }
        }
    }
    
    func setupCurrentUser(context: NSManagedObjectContext) {
        let request: NSFetchRequest<User> = User.fetchRequest()
        
        do {
            let users = try context.fetch(request)
            
            if let existingUser = users.first {
                checkAndSetUserSince(for: existingUser, context: context)
            } else {
                let newUser = User(context: context)
                newUser.userSince = Date()
                
                // Use the computed property from the extension
                if let receiptURL = Bundle.main.appStoreReceiptURL {
                    let isDownloadedFromTestFlight = receiptURL.lastPathComponent == "sandboxReceipt"
                    // Use the value of isDownloadedFromTestFlight to determine if the app is running through TestFlight Beta
                    
                    if isDownloadedFromTestFlight {
                        newUser.memberType = .betaTester
                    } else {
                        newUser.memberType = .listener
                    }
                }
                
                try context.save()
                print("New user created with userSince: \(newUser.userSince!)")
            }
        } catch {
            print("Failed to fetch or create user: \(error)")
        }
    }
}
