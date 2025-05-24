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
        
        setupCurrentUser(context: PersistenceController.shared.container.viewContext)

        // Keep cleanup task for old episodes
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.bradyv.Peapod.Dev.deleteOldEpisodes.v1", using: nil) { task in
            print("🚀 BGTask fired: com.bradyv.Peapod.Dev.deleteOldEpisodes.v1")
            self.handleOldEpisodeCleanup(task: task as! BGAppRefreshTask)
        }
        
        scheduleEpisodeCleanup()
        
        // Request notification permissions immediately
        requestNotificationPermissions()
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
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
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 Registered for remote notifications")
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    // 🆕 Handle background push notifications
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📱 Received remote notification in background")
        
        // Force refresh feeds when receiving push notification
        EpisodeRefresher.forceRefreshForNotification {
            completionHandler(.newData)
        }
    }
    
    // MARK: - Notification Handling
    
    // When user taps a notification
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        print("🔔 User tapped notification: \(userInfo)")
        
        // Clear badge immediately
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        // Handle both local and push notifications
        if let episodeID = userInfo["episodeID"] as? String {
            print("🔍 Looking for episode with ID: \(episodeID)")
            
            // Store the episode ID for cold start scenarios
            AppDelegate.pendingNotificationEpisodeID = episodeID
            
            // Force refresh to ensure we have the latest episodes
            EpisodeRefresher.forceRefreshForNotification {
                // After refresh, try to find and open the episode
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.findAndOpenEpisode(episodeID: episodeID)
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
        print("🔔 Received notification while app in foreground: \(userInfo)")
        
        // Force refresh when notification received in foreground
        EpisodeRefresher.forceRefreshForNotification()
        
        // Show notification even when app is in foreground
        completionHandler([.alert, .sound, .badge])
    }
    
    // 🆕 Helper to find episode by Firebase episode ID format
    private func findAndOpenEpisode(episodeID: String) {
        let context = PersistenceController.shared.container.viewContext
        
        // Firebase episode IDs are in format: encodedFeedUrl_guid
        // We need to decode the feed URL and find the episode by GUID
        let components = episodeID.components(separatedBy: "_")
        guard components.count >= 2 else {
            print("❌ Invalid episode ID format: \(episodeID)")
            return
        }
        
        let encodedFeedUrl = components[0]
        let guid = components.dropFirst().joined(separator: "_") // Rejoin in case GUID contains underscores
        
        // Decode the feed URL
        guard let feedUrl = encodedFeedUrl.removingPercentEncoding else {
            print("❌ Could not decode feed URL: \(encodedFeedUrl)")
            return
        }
        
        print("🔍 Searching for episode with GUID: \(guid) in feed: \(feedUrl)")
        
        // Find episode by GUID and feed URL
        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "guid == %@ AND podcast.feedUrl == %@", guid, feedUrl)
        fetchRequest.fetchLimit = 1
        
        do {
            if let foundEpisode = try context.fetch(fetchRequest).first {
                print("✅ Found episode: \(foundEpisode.title ?? "Unknown")")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .didTapEpisodeNotification, object: foundEpisode.id)
                }
            } else {
                print("❌ Could not find episode with GUID: \(guid) in feed: \(feedUrl)")
                // Try a broader search by GUID only as fallback
                let fallbackRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                fallbackRequest.predicate = NSPredicate(format: "guid == %@", guid)
                fallbackRequest.fetchLimit = 1
                
                if let fallbackEpisode = try context.fetch(fallbackRequest).first {
                    print("✅ Found episode via fallback search: \(fallbackEpisode.title ?? "Unknown")")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .didTapEpisodeNotification, object: fallbackEpisode.id)
                    }
                } else {
                    print("❌ Episode not found even with fallback search")
                }
            }
        } catch {
            print("❌ Error searching for episode: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Push notifications authorized")
            } else if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            } else {
                print("❌ Notification permission denied")
            }
        }
    }
    
    private func sendTokenToBackend(token: String) {
        guard let user = getCurrentUser() else {
            print("❌ No current user found")
            return
        }
        
        // Get user's subscribed podcasts
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        
        do {
            let subscribedPodcasts = try context.fetch(request)
            let feedUrls = subscribedPodcasts.compactMap { $0.feedUrl }
            
            let cleanUserID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            print("✅ Using UUID user ID for Firebase: \(cleanUserID)")
            
            // Send to Firebase Functions using Firebase SDK
            let functions = Functions.functions()
            let registerUser = functions.httpsCallable("registerUser")
            
            let data: [String: Any] = [
                "fcmToken": token,
                "userID": cleanUserID,
                "subscribedFeeds": feedUrls,
                "environment": getCurrentEnvironment()
            ]
            
            registerUser.call(data) { result, error in
                if let error = error {
                    print("❌ Failed to register user with Firebase Functions: \(error)")
                } else {
                    print("✅ User registered successfully with Firebase Functions")
                }
            }
            
        } catch {
            print("❌ Failed to fetch subscribed podcasts: \(error)")
        }
    }
    
    private func getCurrentEnvironment() -> String {
        guard let bundleId = Bundle.main.bundleIdentifier else { return "unknown" }
        
        switch bundleId {
        case "com.bradyv.Peapod.Debug":
            return "debug"
        case "com.bradyv.Peapod.Dev":
            return "dev"
        default:
            return "prod"
        }
    }
    
    private func getCurrentUser() -> User? {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        return try? context.fetch(request).first
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
