//
//  AppDelegate.swift
//  Peapod
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
import AVFoundation
import StoreKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    static var pendingNotificationEpisodeID: String?
    
    lazy var episodesViewModel: EpisodesViewModel = {
        let viewModel = EpisodesViewModel()
        viewModel.setup(context: PersistenceController.shared.container.viewContext)
        return viewModel
    }()
    
    override init() {
        super.init()
        print("🧬 AppDelegate initialized")
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }
    
    func application(_ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        AppAppearance.setupAppearance()
        UserManager.shared.setupCurrentUser()
        
        Task {
            await SubscriptionManager.shared.loadProducts()
            await SubscriptionManager.shared.checkSubscriptionStatus()
        }
        
        configureGlobalAudioSession()
        setupAppLifecycleNotifications()
        
        // Initialize the episodes view model early
        _ = episodesViewModel
        LogManager.shared.info("EpisodesViewModel initialized early in AppDelegate")
        
        // Schedule the first cleanup
        checkAndRunWeeklyCleanup()
        
        checkAndRegisterForNotificationsIfGranted()
        
        return true
    }
    
    // MARK: - Setup Audio
    
    func configureGlobalAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [
                    .allowAirPlay,
                    .allowBluetoothA2DP,
                    .allowBluetoothHFP,
                    .duckOthers
                ]
            )
            
            // NEW: Optimize buffer size for faster response
            try session.setPreferredIOBufferDuration(0.005)  // 5ms for responsive playback
            
            // NEW: Ensure high sample rate for quality
            try session.setPreferredSampleRate(44100)
            
            try session.setActive(true)
            
            LogManager.shared.info("Audio session configured and activated")
        } catch {
            LogManager.shared.error("Failed to configure audio session: \(error)")
        }
    }

    // MARK: - App Lifecycle Notifications
    
    func setupAppLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appWillResignActive() {
        // Save playback position immediately when app loses focus
        AudioPlayerManager.shared.savePositionSync()
    }

    // MARK: - Firebase Messaging Delegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔥 Firebase registration token: \(fcmToken ?? "nil")")
        
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
                    UserDefaults.standard.set(true, forKey: "notificationsGranted")
                    UserDefaults.standard.set(true, forKey: "notificationsAsked")
                }
            }
        }
    }

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
        
        // ✅ Only sync if user has enabled notifications in-app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let appNotificationsEnabled = UserDefaults.standard.bool(forKey: "appNotificationsEnabled")
            
            if appNotificationsEnabled {
                LogManager.shared.info("🔄 APNs token received, syncing subscriptions...")
                SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
            } else {
                LogManager.shared.info("ℹ️ APNs token received but app notifications disabled - skipping sync")
            }
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        LogManager.shared.error("❌ Failed to register for remote notifications: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        LogManager.shared.info("📱 Received remote notification - app state: \(application.applicationState.rawValue)")
        LogManager.shared.info("📱 Notification payload: \(userInfo)")
        
        if let messageID = userInfo["gcm.message_id"] as? String {
            LogManager.shared.info("🔥 Firebase message ID: \(messageID)")
        }
        
        let refreshStartTime = Date()
        LogManager.shared.info("🔄 Starting force refresh for notification at \(refreshStartTime)")
        
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
        
        EpisodeRefresher.forceRefreshForNotification {
            let refreshDuration = Date().timeIntervalSince(refreshStartTime)
            LogManager.shared.info("✅ Background refresh completed in \(String(format: "%.2f", refreshDuration))s")
            safeComplete(.newData)
        }
        
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
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        LogManager.shared.info("🔔 User tapped notification: \(userInfo)")
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        if let episodeID = userInfo["episodeID"] as? String {
            print("🔍 Looking for episode with ID: \(episodeID)")
            AppDelegate.pendingNotificationEpisodeID = episodeID
            
            if findAndOpenEpisode(episodeID: episodeID) {
                LogManager.shared.info("✅ Episode found immediately, no refresh needed")
                completionHandler()
                return
            }
            
            LogManager.shared.info("🔄 Episode not found, forcing refresh...")
            EpisodeRefresher.forceRefreshForNotification {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !self.findAndOpenEpisode(episodeID: episodeID) {
                        LogManager.shared.error("❌ Episode still not found after refresh")
                    }
                }
            }
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        LogManager.shared.info("🔔 Received notification while app in foreground: \(userInfo)")
        
        EpisodeRefresher.forceRefreshForNotification()
        completionHandler([.alert, .sound, .badge])
    }
    
    @discardableResult
    private func findAndOpenEpisode(episodeID: String) -> Bool {
        let context = PersistenceController.shared.container.viewContext
        
        print("🔍 Searching for episode with Firebase ID: '\(episodeID)'")
        
        let podcastRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        podcastRequest.predicate = NSPredicate(format: "isSubscribed == YES")
        
        do {
            let subscribedPodcasts = try context.fetch(podcastRequest)
            
            for podcast in subscribedPodcasts {
                guard let feedUrl = podcast.feedUrl else { continue }
                
                let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                episodeRequest.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
                
                do {
                    let episodes = try context.fetch(episodeRequest)
                    
                    for episode in episodes {
                        guard let guid = episode.guid else { continue }
                        
                        let combined = "\(feedUrl)_\(guid)"
                        let hash = combined.md5Hash()
                        
                        if hash == episodeID {
                            LogManager.shared.info("✅ Found episode by hash match: \(episode.title ?? "Unknown")")
                            print("   🔍 Matched: \(feedUrl) + \(guid) = \(hash)")
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
        
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        
        do {
            let subscribedPodcasts = try context.fetch(request)
            let feedUrls = subscribedPodcasts.compactMap { $0.feedUrl }
            
            let cleanUserID = UserManager.shared.cleanUserID
            LogManager.shared.info("✅ Using UUID user ID for Firebase: \(cleanUserID)")
            
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
    
    // MARK: - Weekly Cleanup
    
    /// Manual cleanup for testing - call this from your UI during development
    func debugPerformCleanupNow() {
        LogManager.shared.info("🧪 DEBUG: Starting manual cleanup")
        print("🧪 DEBUG: Starting manual cleanup")
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform { [self] in
            do {
                let (deletedEpisodes, deletedPodcasts, deletedPlayback) = try cleanupUnusedData(in: context)
                LogManager.shared.info("✅ DEBUG cleanup completed: \(deletedEpisodes) episodes, \(deletedPodcasts) podcasts, \(deletedPlayback) playback deleted")
                print("✅ DEBUG cleanup completed: \(deletedEpisodes) episodes, \(deletedPodcasts) podcasts, \(deletedPlayback) playback deleted")
            } catch {
                LogManager.shared.error("❌ DEBUG cleanup failed: \(error)")
                print("❌ DEBUG cleanup failed: \(error)")
            }
        }
    }
    
    /// Performs comprehensive weekly cleanup of unused episodes and unsubscribed podcasts
    func performWeeklyCleanup() {
        LogManager.shared.info("🧹 Starting weekly cleanup")
        print("🧹 Starting weekly cleanup")
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform { [self] in
            do {
                let (deletedEpisodes, deletedPodcasts, deletedPlayback) = try cleanupUnusedData(in: context)
                
                // Log the results
                LogManager.shared.info("✅ Weekly cleanup completed: \(deletedEpisodes) episodes, \(deletedPodcasts) podcasts, \(deletedPlayback) playback records deleted")
                print("✅ Weekly cleanup completed: \(deletedEpisodes) episodes, \(deletedPodcasts) podcasts, \(deletedPlayback) playback records deleted")
                
                // Mark that cleanup ran successfully
                UserDefaults.standard.set(Date(), forKey: "lastSuccessfulWeeklyCleanup")
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .didCompleteWeeklyCleanup, object: nil)
                }
            } catch {
                LogManager.shared.error("❌ Weekly cleanup failed: \(error)")
                print("❌ Weekly cleanup failed: \(error)")
            }
        }
    }
    
    private func cleanupOrphanedPlaybackRecords(context: NSManagedObjectContext) {
        // Get all existing episode IDs
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        episodeRequest.propertiesToFetch = ["id"]
        episodeRequest.returnsObjectsAsFaults = false
        
        let allEpisodes = (try? context.fetch(episodeRequest)) ?? []
        let validEpisodeIds = Set(allEpisodes.compactMap { $0.id })
        
        // Find playback records that point to non-existent episodes
        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
        let allPlaybacks = (try? context.fetch(playbackRequest)) ?? []
        
        let orphanedPlaybacks = allPlaybacks.filter { playback in
            guard let episodeId = playback.episodeId else { return true } // Delete playbacks with nil episodeId
            return !validEpisodeIds.contains(episodeId)
        }
        
        guard !orphanedPlaybacks.isEmpty else {
            LogManager.shared.info("No orphaned playback records found")
            return
        }
        
        LogManager.shared.info("Found \(orphanedPlaybacks.count) orphaned playback records to delete")
        
        for playback in orphanedPlaybacks {
            LogManager.shared.info("   Deleting orphaned playback for episode: \(playback.episodeId ?? "nil")")
            context.delete(playback)
        }
        
        if context.hasChanges {
            do {
                try context.save()
                LogManager.shared.info("Successfully deleted \(orphanedPlaybacks.count) orphaned playback records")
            } catch {
                LogManager.shared.error("Failed to save orphan cleanup: \(error)")
            }
        }
    }
    
    /// Core cleanup logic that removes unused data based on subscription status
    private func cleanupUnusedData(in context: NSManagedObjectContext) throws -> (episodesDeleted: Int, podcastsDeleted: Int, playbackDeleted: Int) {
        var deletedEpisodes = 0
        var deletedPodcasts = 0
        var deletedPlayback = 0
        
        LogManager.shared.info("🧹 Starting cleanup process")
        print("🧹 Starting cleanup process")
        
        // Get subscription status mappings upfront
        let subscribedPodcastIds = getSubscribedPodcastIds(context: context)
        let unsubscribedPodcastIds = try getUnsubscribedPodcastIds(context: context)
        
        print("📊 Subscribed podcasts: \(subscribedPodcastIds.count)")
        print("📊 Unsubscribed podcasts: \(unsubscribedPodcastIds.count)")
        
        // STEP 1: Clean playback records with different rules for subscribed vs unsubscribed
        deletedPlayback = try cleanupPlaybackRecords(
            subscribedPodcastIds: subscribedPodcastIds,
            unsubscribedPodcastIds: unsubscribedPodcastIds,
            context: context
        )
        
        // STEP 2: Remove episodes from unsubscribed podcasts that have no meaningful playback
        deletedEpisodes = try cleanupEpisodesFromUnsubscribedPodcasts(
            unsubscribedPodcastIds: unsubscribedPodcastIds,
            context: context
        )
        
        // STEP 3: Remove all unsubscribed podcasts
        deletedPodcasts = try cleanupUnsubscribedPodcasts(context: context)
        
        // STEP 4: Cleanup orphaned playback
        cleanupOrphanedPlaybackRecords(context: context)
        
        // Save all changes
        if context.hasChanges {
            try context.save()
            LogManager.shared.info("✅ Context saved successfully")
            print("✅ Context saved successfully")
        } else {
            LogManager.shared.info("ℹ️ No changes to save")
            print("ℹ️ No changes to save")
        }
        
        return (deletedEpisodes, deletedPodcasts, deletedPlayback)
    }

    /// Clean playback records with different rules for subscribed vs unsubscribed podcasts
    private func cleanupPlaybackRecords(
        subscribedPodcastIds: [String],
        unsubscribedPodcastIds: [String],
        context: NSManagedObjectContext
    ) throws -> Int {
        var deletedCount = 0
        
        // Get episode IDs for each subscription category
        let subscribedEpisodeIds = try getEpisodeIds(forPodcasts: subscribedPodcastIds, context: context)
        let unsubscribedEpisodeIds = try getEpisodeIds(forPodcasts: unsubscribedPodcastIds, context: context)
        
        // Clean subscribed podcast playback (conservative - keep if >5 minutes)
        if !subscribedEpisodeIds.isEmpty {
            let subscribedPlaybackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
            subscribedPlaybackRequest.predicate = NSPredicate(format:
                "isQueued == NO AND isPlayed == NO AND isFav == NO AND playbackPosition <= 300 AND episodeId IN %@",
                subscribedEpisodeIds)
            
            let subscribedPlaybackToDelete = try context.fetch(subscribedPlaybackRequest)
            print("📊 Found \(subscribedPlaybackToDelete.count) low-engagement playback records from subscribed podcasts")
            
            for record in subscribedPlaybackToDelete {
                context.delete(record)
                deletedCount += 1
            }
        }
        
        // Clean unsubscribed podcast playback (aggressive - any without meaningful flags)
        if !unsubscribedEpisodeIds.isEmpty {
            let unsubscribedPlaybackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
            unsubscribedPlaybackRequest.predicate = NSPredicate(format:
                "isQueued == NO AND isPlayed == NO AND isFav == NO AND episodeId IN %@",
                unsubscribedEpisodeIds)
            
            let unsubscribedPlaybackToDelete = try context.fetch(unsubscribedPlaybackRequest)
            print("📊 Found \(unsubscribedPlaybackToDelete.count) non-meaningful playback records from unsubscribed podcasts")
            
            for record in unsubscribedPlaybackToDelete {
                context.delete(record)
                deletedCount += 1
            }
        }
        
        LogManager.shared.info("🗑️ Deleted \(deletedCount) playback records")
        print("🗑️ Deleted \(deletedCount) playback records")
        return deletedCount
    }

    /// Remove episodes from unsubscribed podcasts that have no meaningful playback data
    private func cleanupEpisodesFromUnsubscribedPodcasts(
        unsubscribedPodcastIds: [String],
        context: NSManagedObjectContext
    ) throws -> Int {
        var deletedCount = 0
        
        guard !unsubscribedPodcastIds.isEmpty else {
            print("ℹ️ No unsubscribed podcasts found")
            return 0
        }
        
        // Get episodes that have meaningful interaction (played, queued, favorited, or >5 mins playback)
        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
        playbackRequest.predicate = NSPredicate(format: "isPlayed == YES OR isQueued == YES OR isFav == YES OR playbackPosition > 300")
        let meaningfulPlaybackRecords = try context.fetch(playbackRequest)
        let episodeIdsToPreserve = Set(meaningfulPlaybackRecords.compactMap { $0.episodeId })
        
        print("🔍 Found \(episodeIdsToPreserve.count) episodes with meaningful interaction to preserve")
        
        // Find episodes from unsubscribed podcasts
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        var predicates: [NSPredicate] = [
            NSPredicate(format: "podcastId IN %@", unsubscribedPodcastIds)
        ]
        
        // Exclude episodes with meaningful interaction
        if !episodeIdsToPreserve.isEmpty {
            predicates.append(NSPredicate(format: "NOT (id IN %@)", Array(episodeIdsToPreserve)))
        }
        
        episodeRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        let episodesToDelete = try context.fetch(episodeRequest)
        print("🗑️ Found \(episodesToDelete.count) unused episodes from unsubscribed podcasts to delete")
        
        for episode in episodesToDelete {
            let title = episode.title ?? "Untitled"
            let podcastTitle = episode.podcast?.title ?? "Unknown Podcast"
            print("   - Deleting episode: \(title) from \(podcastTitle)")
            context.delete(episode)
            deletedCount += 1
        }
        
        LogManager.shared.info("🗑️ Deleted \(deletedCount) episodes from unsubscribed podcasts")
        return deletedCount
    }

    // Remove unsubscribed podcasts that have no episodes with meaningful playback
    private func cleanupUnsubscribedPodcasts(context: NSManagedObjectContext) throws -> Int {
        var deletedCount = 0
        
        // Get all episodes with meaningful interaction
        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
        playbackRequest.predicate = NSPredicate(format: "isPlayed == YES OR isQueued == YES OR isFav == YES OR playbackPosition > 300")
        let meaningfulPlaybackRecords = try context.fetch(playbackRequest)
        let episodeIdsWithMeaningfulPlayback = Set(meaningfulPlaybackRecords.compactMap { $0.episodeId })
        
        print("🔍 Found \(episodeIdsWithMeaningfulPlayback.count) episodes with meaningful playback")
        
        // Get podcast IDs that have episodes with meaningful playback
        var podcastIdsToPreserve = Set<String>()
        if !episodeIdsWithMeaningfulPlayback.isEmpty {
            let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            episodeRequest.predicate = NSPredicate(format: "id IN %@", Array(episodeIdsWithMeaningfulPlayback))
            let episodesWithMeaningfulPlayback = try context.fetch(episodeRequest)
            podcastIdsToPreserve = Set(episodesWithMeaningfulPlayback.compactMap { $0.podcastId })
            
            print("🔍 Found \(podcastIdsToPreserve.count) podcasts with meaningful episode playback to preserve")
        }
        
        // Find unsubscribed podcasts WITHOUT meaningful episode playback
        let podcastRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        var predicates: [NSPredicate] = [
            NSPredicate(format: "isSubscribed == NO")
        ]
        
        // Exclude podcasts that have episodes with meaningful playback
        if !podcastIdsToPreserve.isEmpty {
            predicates.append(NSPredicate(format: "NOT (id IN %@)", Array(podcastIdsToPreserve)))
        }
        
        podcastRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        let unsubscribedPodcasts = try context.fetch(podcastRequest)
        print("🗑️ Found \(unsubscribedPodcasts.count) unsubscribed podcasts without meaningful playback to delete")
        
        for podcast in unsubscribedPodcasts {
            let title = podcast.title ?? "Unknown Podcast"
            print("   - Deleting podcast: \(title)")
            context.delete(podcast)
            deletedCount += 1
        }
        
        LogManager.shared.info("🗑️ Deleted \(deletedCount) unsubscribed podcasts")
        return deletedCount
    }

    /// Helper function to get episode IDs for specific podcasts
    private func getEpisodeIds(forPodcasts podcastIds: [String], context: NSManagedObjectContext) throws -> [String] {
        guard !podcastIds.isEmpty else { return [] }
        
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId IN %@", podcastIds)
        
        let episodes = try context.fetch(request)
        return episodes.compactMap { $0.id }
    }

    /// Helper to get unsubscribed podcast IDs
    private func getUnsubscribedPodcastIds(context: NSManagedObjectContext) throws -> [String] {
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == NO")
        
        let podcasts = try context.fetch(request)
        return podcasts.compactMap { $0.id }
    }
    
    /// Background task handler for weekly cleanup
    private func handleWeeklyCleanup(task: BGAppRefreshTask) {
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform { [self] in
            do {
                let (deletedEpisodes, deletedPodcasts, deletedPlayback) = try cleanupUnusedData(in: context)
                LogManager.shared.info("✅ Background weekly cleanup completed: \(deletedEpisodes) episodes, \(deletedPodcasts) podcasts, \(deletedPlayback) playback deleted")
                
                // Mark that cleanup ran successfully
                UserDefaults.standard.set(Date(), forKey: "lastSuccessfulWeeklyCleanup")
                
                task.setTaskCompleted(success: true)
            } catch {
                LogManager.shared.error("❌ Background weekly cleanup failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }

    func checkAndRunWeeklyCleanup() {
        let lastCleanupKey = "lastSuccessfulWeeklyCleanup"
        let now = Date()
        
        // Get the last cleanup date (nil on first launch)
        let lastCleanup = UserDefaults.standard.object(forKey: lastCleanupKey) as? Date
        
        // If never cleaned before, run it now
        guard let lastCleanup = lastCleanup else {
            LogManager.shared.info("🧹 First launch - running initial cleanup")
            print("🧹 First launch - running initial cleanup")
            performWeeklyCleanup()
            return
        }
        
        // Check if 7 days have passed
        let timeSinceLastCleanup = now.timeIntervalSince(lastCleanup)
        let sevenDaysInSeconds: TimeInterval = 60 * 60 * 24 * 7
        
        if timeSinceLastCleanup >= sevenDaysInSeconds {
            let daysSinceCleanup = Int(timeSinceLastCleanup / (60 * 60 * 24))
            LogManager.shared.info("🧹 \(daysSinceCleanup) days since last cleanup - running now")
            print("🧹 \(daysSinceCleanup) days since last cleanup - running now")
            performWeeklyCleanup()
        } else {
            let hoursRemaining = Int((sevenDaysInSeconds - timeSinceLastCleanup) / 3600)
            LogManager.shared.info("✅ Cleanup not needed yet - next cleanup in ~\(hoursRemaining) hours")
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
    static let didCompleteWeeklyCleanup = Notification.Name("didCompleteWeeklyCleanup")
}
