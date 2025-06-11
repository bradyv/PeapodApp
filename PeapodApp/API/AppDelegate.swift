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
import FirebaseMessaging
import FirebaseFunctions
import CryptoKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    static var pendingNotificationEpisodeID: String?
    
    override init() {
        super.init()
        print("🧬 AppDelegate initialized")
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        UserManager.shared.setupCurrentUser()
        
        performStartupCleanup()

        // Keep cleanup task for old episodes
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.bradyv.Peapod.Dev.deleteOldEpisodes.v1", using: nil) { task in
            print("🚀 BGTask fired: com.bradyv.Peapod.Dev.deleteOldEpisodes.v1")
            self.handleOldEpisodeCleanup(task: task as! BGAppRefreshTask)
        }
        
        scheduleEpisodeCleanup()
        
        // Check and register for remote notifications
        checkAndRegisterForNotificationsIfGranted()
        
        return true
    }

    // MARK: - Firebase Messaging Delegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔥 Firebase registration token: \(fcmToken ?? "nil")")
        
        // Send token to your backend
        if let token = fcmToken {
            sendTokenToBackend(token: token)
        }
    }
    
    // MARK: - Remote Notifications
    private func checkAndRegisterForNotificationsIfGranted() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .authorized {
                    UIApplication.shared.registerForRemoteNotifications()
                    
                    // Update AppStorage to reflect current status
                    UserDefaults.standard.set(true, forKey: "notificationsGranted")
                    UserDefaults.standard.set(true, forKey: "notificationsAsked")
                }
            }
        }
    }

    // Keep the requestNotificationPermissions method for when it's called from the RequestNotificationsView
    func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                LogManager.shared.info("✅ Push notifications authorized")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else if let error = error {
                LogManager.shared.error("❌ Notification permission error: \(error.localizedDescription)")
            } else {
                LogManager.shared.error("❌ Notification permission denied")
            }
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 Registered for remote notifications")
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        LogManager.shared.error("❌ Failed to register for remote notifications: \(error)")
    }
    
    // ENHANCED: Handle background push notifications with better logging
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        LogManager.shared.info("📱 Received remote notification - app state: \(application.applicationState.rawValue)")
        LogManager.shared.info("📱 Notification payload: \(userInfo)")
        
        // Check if this is a Firebase message
        if let messageID = userInfo["gcm.message_id"] as? String {
            LogManager.shared.info("🔥 Firebase message ID: \(messageID)")
        }
        
        // Track the refresh start
        let refreshStartTime = Date()
        LogManager.shared.info("🔔 Starting force refresh for notification at \(refreshStartTime)")
        
        // 🚀 NEW: Use a flag to ensure completion handler is only called once
        var hasCompleted = false
        let completionLock = NSLock()
        
        func safeComplete(_ result: UIBackgroundFetchResult) {
            completionLock.lock()
            defer { completionLock.unlock() }
            
            if !hasCompleted {
                hasCompleted = true
                completionHandler(result)
            }
        }
        
        // Force refresh feeds when receiving push notification
        EpisodeRefresher.forceRefreshForNotification {
            let refreshDuration = Date().timeIntervalSince(refreshStartTime)
            LogManager.shared.info("✅ Background refresh completed in \(String(format: "%.2f", refreshDuration))s")
            safeComplete(.newData)
        }
        
        // Timeout protection - only call if refresh hasn't completed yet
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            completionLock.lock()
            if !hasCompleted {
                print("⏰ Background refresh timeout after 25 seconds")
                hasCompleted = true
                completionHandler(.noData)
            }
            completionLock.unlock()
        }
    }
    
    // MARK: - Notification Handling
    
    // ENHANCED: When user taps a notification with better flow control
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        LogManager.shared.info("🔔 User tapped notification: \(userInfo)")
        
        // Clear badge immediately
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        // Handle both local and push notifications
        if let episodeID = userInfo["episodeID"] as? String {
            print("🔍 Looking for episode with ID: \(episodeID)")
            
            // Store the episode ID for ContentView to handle
            AppDelegate.pendingNotificationEpisodeID = episodeID
            
            // Immediately try to find the episode first
            if findAndOpenEpisode(episodeID: episodeID) {
                LogManager.shared.info("✅ Episode found immediately, no refresh needed")
                completionHandler()
                return
            }
            
            // If not found, do a refresh and try again
            LogManager.shared.info("🔄 Episode not found, forcing refresh...")
            EpisodeRefresher.forceRefreshForNotification {
                // After refresh, try to find and open the episode
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !self.findAndOpenEpisode(episodeID: episodeID) {
                        LogManager.shared.error("❌ Episode still not found after refresh")
                    }
                }
            }
        }
        
        completionHandler()
    }
    
    // Handle foreground notifications
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        LogManager.shared.info("🔔 Received notification while app in foreground: \(userInfo)")
        
        // Force refresh when notification received in foreground
        EpisodeRefresher.forceRefreshForNotification()
        
        // Show notification even when app is in foreground
        completionHandler([.alert, .sound, .badge])
    }
    
    // ENHANCED: Helper to find episode by Firebase episode ID format with return value
    @discardableResult
    private func findAndOpenEpisode(episodeID: String) -> Bool {
        let context = PersistenceController.shared.container.viewContext
        
        print("🔍 Searching for episode with Firebase ID: '\(episodeID)'")
        
        // Firebase now sends MD5 hashes, so we need to reverse-engineer
        // Since we can't reverse MD5, we'll search all episodes and match against generated hashes
        
        // Strategy 1: Direct search by reconstructing possible episode IDs
        // We'll check all episodes in subscribed podcasts and see if any match the hash
        let podcastRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        podcastRequest.predicate = NSPredicate(format: "isSubscribed == YES")
        
        do {
            let subscribedPodcasts = try context.fetch(podcastRequest)
            
            for podcast in subscribedPodcasts {
                guard let feedUrl = podcast.feedUrl else { continue }
                
                // Get episodes from this podcast
                let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                episodeRequest.predicate = NSPredicate(format: "podcast == %@", podcast)
                
                do {
                    let episodes = try context.fetch(episodeRequest)
                    
                    for episode in episodes {
                        guard let guid = episode.guid else { continue }
                        
                        // Recreate the hash that Firebase would have generated
                        let combined = "\(feedUrl)_\(guid)"
                        let hash = combined.md5Hash()
                        
                        if hash == episodeID {
                            LogManager.shared.info("✅ Found episode by hash match: \(episode.title ?? "Unknown")")
                            print("   📍 Matched: \(feedUrl) + \(guid) = \(hash)")
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .didTapEpisodeNotification, object: episode.id)
                            }
                            return true
                        }
                    }
                } catch {
                    LogManager.shared.error("❌ Error fetching episodes for podcast \(podcast.title ?? "Unknown"): \(error)")
                }
            }
            
        } catch {
            LogManager.shared.error("❌ Error fetching subscribed podcasts: \(error)")
        }
        
        LogManager.shared.error("❌ Episode not found with Firebase ID: \(episodeID)")
        return false
    }
    
    // MARK: - Helper Methods
    private func sendTokenToBackend(token: String) {
        guard UserManager.shared.currentUser != nil else {
            LogManager.shared.error("❌ No current user found")
            return
        }
        
        // Get user's subscribed podcasts
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        
        do {
            let subscribedPodcasts = try context.fetch(request)
            let feedUrls = subscribedPodcasts.compactMap { $0.feedUrl }
            
            let cleanUserID = UserManager.shared.cleanUserID
            LogManager.shared.info("✅ Using UUID user ID for Firebase: \(cleanUserID)")
            
            // Send to Firebase Functions using Firebase SDK
            let functions = Functions.functions()
            let registerUser = functions.httpsCallable("registerUser")
            
            let data: [String: Any] = [
                "fcmToken": token,
                "userID": cleanUserID,
                "subscribedFeeds": feedUrls,
                "environment": UserManager.shared.currentEnvironment
            ]
            
            registerUser.call(data) { result, error in
                if let error = error {
                    LogManager.shared.error("❌ Failed to register user with Firebase Functions: \(error)")
                } else {
                    LogManager.shared.info("✅ User registered successfully with Firebase Functions")
                }
            }
            
        } catch {
            LogManager.shared.error("❌ Failed to fetch subscribed podcasts: \(error)")
        }
    }
    
    // MARK: - Background Tasks (keeping cleanup only)
    
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
                LogManager.shared.info("✅ DEBUG: Deleted \(episodes.count) episode(s)")
            } catch {
                LogManager.shared.error("❌ DEBUG purge failed: \(error)")
            }
        }
    }

    // MARK: - Cleanup Functions

    /// Performs comprehensive cleanup of unsubscribed podcasts and episodes on app startup
    private func performStartupCleanup() {
        LogManager.shared.info("🧹 Starting app startup cleanup")
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            do {
                let (deletedEpisodes, deletedPodcasts) = try self.cleanupUnsubscribedContent(in: context)
                
                LogManager.shared.info("✅ Startup cleanup completed: \(deletedEpisodes) episodes, \(deletedPodcasts) podcasts deleted")
                
                // Optional: Post notification for UI updates if needed
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .didCompleteStartupCleanup, object: nil)
                }
                
            } catch {
                LogManager.shared.error("❌ Startup cleanup failed: \(error)")
            }
        }
    }

    /// Core cleanup logic that can be reused by both startup and background tasks
    private func cleanupUnsubscribedContent(in context: NSManagedObjectContext) throws -> (episodesDeleted: Int, podcastsDeleted: Int) {
        var deletedEpisodes = 0
        var deletedPodcasts = 0
        
        // Step 1: Clean up episodes from unsubscribed podcasts (but preserve saved/played/queued ones)
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        episodeRequest.predicate = NSPredicate(format:
            "podcast.isSubscribed == NO AND isSaved == NO AND isPlayed == NO AND isQueued == NO"
        )
        
        let episodesToDelete = try context.fetch(episodeRequest)
        LogManager.shared.info("🗑️ Found \(episodesToDelete.count) episodes to delete from unsubscribed podcasts")
        
        for episode in episodesToDelete {
            let title = episode.title ?? "Untitled"
            let podcastTitle = episode.podcast?.title ?? "Unknown Podcast"
            LogManager.shared.debug("   - Deleting episode: \(title) from \(podcastTitle)")
            context.delete(episode)
            deletedEpisodes += 1
        }
        
        // Step 2: Clean up podcasts that are unsubscribed and have no remaining episodes
        let podcastRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        podcastRequest.predicate = NSPredicate(format: "isSubscribed == NO")
        
        let unsubscribedPodcasts = try context.fetch(podcastRequest)
        LogManager.shared.info("🔍 Found \(unsubscribedPodcasts.count) unsubscribed podcasts to evaluate")
        
        for podcast in unsubscribedPodcasts {
            // Check if podcast has any remaining episodes (saved, played, or queued)
            let remainingEpisodesRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            remainingEpisodesRequest.predicate = NSPredicate(format:
                "podcast == %@ AND (isSaved == YES OR isPlayed == YES OR isQueued == YES)",
                podcast
            )
            remainingEpisodesRequest.fetchLimit = 1 // We only need to know if any exist
            
            let remainingEpisodes = try context.fetch(remainingEpisodesRequest)
            
            if remainingEpisodes.isEmpty {
                // Safe to delete this podcast as it has no saved/played/queued episodes
                let title = podcast.title ?? "Unknown Podcast"
                LogManager.shared.debug("   - Deleting podcast: \(title)")
                context.delete(podcast) // This will cascade delete any remaining episodes
                deletedPodcasts += 1
            } else {
                LogManager.shared.debug("   - Keeping podcast: \(podcast.title ?? "Unknown") (has \(remainingEpisodes.count) preserved episodes)")
            }
        }
        
        // Save all changes
        if context.hasChanges {
            try context.save()
        }
        
        return (deletedEpisodes, deletedPodcasts)
    }

    /// Updated background task handler to use the same cleanup logic
    private func handleOldEpisodeCleanup(task: BGAppRefreshTask) {
        scheduleEpisodeCleanup() // Reschedule for next week
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            do {
                let (deletedEpisodes, deletedPodcasts) = try self.cleanupUnsubscribedContent(in: context)
                LogManager.shared.info("✅ Background cleanup completed: \(deletedEpisodes) episodes, \(deletedPodcasts) podcasts deleted")
                task.setTaskCompleted(success: true)
            } catch {
                LogManager.shared.error("❌ Background cleanup failed: \(error)")
                task.setTaskCompleted(success: false)
            }
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
}

extension String {
    func md5Hash() -> String {
        let data = Data(self.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}


extension Notification.Name {
    static let didCompleteStartupCleanup = Notification.Name("didCompleteStartupCleanup")
}
