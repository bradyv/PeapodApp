//
//  SubscriptionSyncService.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-24.
//

import Foundation
import CoreData
import FirebaseMessaging
import FirebaseFunctions
import UIKit

class SubscriptionSyncService {
    static let shared = SubscriptionSyncService()
    private init() {}
    
    // NEW: Subscribe to a feed's topic
    func subscribeToFeed(feedUrl: String) {
        let topic = createTopicFromFeedUrl(feedUrl)
        
        Messaging.messaging().subscribe(toTopic: topic) { error in
            if let error = error {
                LogManager.shared.error("❌ Failed to subscribe to topic \(topic): \(error)")
            } else {
                LogManager.shared.info("✅ Subscribed to topic: \(topic)")
            }
        }
    }
    
    // NEW: Unsubscribe from a feed's topic
    func unsubscribeFromFeed(feedUrl: String) {
        let topic = createTopicFromFeedUrl(feedUrl)
        
        Messaging.messaging().unsubscribe(fromTopic: topic) { error in
            if let error = error {
                LogManager.shared.error("❌ Failed to unsubscribe from topic \(topic): \(error)")
            } else {
                LogManager.shared.info("✅ Unsubscribed from topic: \(topic)")
            }
        }
    }
    
    // NEW: Helper to create topic name (matches backend)
    private func createTopicFromFeedUrl(_ feedUrl: String) -> String {
        return feedUrl.md5Hash()
    }
    
    // Helper to fetch subscribed podcasts from Core Data
    private func fetchSubscribedPodcasts() -> [Podcast] {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        
        do {
            return try context.fetch(request)
        } catch {
            LogManager.shared.error("❌ Failed to fetch subscribed podcasts: \(error)")
            return []
        }
    }
    
    // Sync all subscriptions - subscribe to topics AND report to backend
    func syncSubscriptionsWithBackend() {
        let subscribedPodcasts = fetchSubscribedPodcasts()
        let feedUrls = subscribedPodcasts.compactMap { $0.feedUrl?.normalizeURL() }
        
        guard !feedUrls.isEmpty else {
            LogManager.shared.info("ℹ️ No feeds to sync")
            return
        }
        
        // 1. Subscribe to FCM topics
        for feedUrl in feedUrls {
            subscribeToFeed(feedUrl: feedUrl)
        }
        
        LogManager.shared.info("✅ Synced \(subscribedPodcasts.count) feed subscriptions")
        
        // 2. Report feeds to backend (with retry logic)
        reportFeedsToBackend()
    }
    
    func reportFeedsToBackend() {
        // Get current subscribed feeds
        let subscriptions = fetchSubscribedPodcasts()
        let feedUrls = subscriptions.compactMap { $0.feedUrl }
        
        guard !feedUrls.isEmpty else {
            LogManager.shared.info("📤 No feeds to report")
            return
        }
        
        LogManager.shared.info("📤 Reporting \(feedUrls.count) feeds to backend...")
        
        let functions = Functions.functions(region: "us-central1")
        
        functions.httpsCallable("reportUserFeeds").call(["feedUrls": feedUrls]) { result, error in
            if let error = error {
                LogManager.shared.error("❌ Failed to report feeds: \(error)")
                
                // ❌ OLD CODE: Don't set this flag on failure!
                // UserDefaults.standard.set(true, forKey: "hasAttemptedToReportFeeds")
                
                // ✅ NEW CODE: Schedule a retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                    self?.reportFeedsToBackend()
                }
                return
            }
            
            if let data = result?.data as? [String: Any],
               let added = data["added"] as? Int,
               let existing = data["existing"] as? Int {
                LogManager.shared.info("✅ Reported feeds to backend: \(added) added, \(existing) existing")
                
                // ✅ Only set flag on SUCCESS
                UserDefaults.standard.set(true, forKey: "hasSuccessfullyReportedFeeds")
            }
        }
    }
    
    func validateBackendFeedCount() {
        let subscriptions = fetchSubscribedPodcasts()
        let localCount = subscriptions.count
        
        LogManager.shared.info("📊 Local subscriptions: \(localCount)")
        
        // Call a new validation endpoint
        let functions = Functions.functions(region: "us-central1")
        functions.httpsCallable("getUserFeedCount").call { result, error in
            if let data = result?.data as? [String: Any],
               let remoteCount = data["count"] as? Int {
                
                LogManager.shared.info("📊 Backend has: \(remoteCount) feeds")
                
                if localCount != remoteCount {
                    LogManager.shared.warning("⚠️ Mismatch! Forcing sync...")
                    
                    // Clear the success flag and retry
                    UserDefaults.standard.removeObject(forKey: "hasSuccessfullyReportedFeeds")
                    self.reportFeedsToBackend()
                }
            }
        }
    }
    
    // Keep existing methods for backwards compatibility if needed
    private func getCurrentEnvironment() -> String {
        guard let bundleId = Bundle.main.bundleIdentifier else { return "unknown" }
        
        switch bundleId {
        case "fm.peapod.debug":
            return "debug"
        case "fm.peapod":
            return "dev"
        default:
            return "prod"
        }
    }
    
    private func getUserID() -> String {
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
}
