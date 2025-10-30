//
//  PodcastSubscriptionManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-10-18.
//

import Foundation
import CoreData
import FirebaseMessaging

/// Centralized manager for handling podcast subscriptions
/// Handles both FCM topic subscriptions and backend reporting in one place
class PodcastSubscriptionManager {
    static let shared = PodcastSubscriptionManager()
    
    private init() {}
    
    // MARK: - Main API
    
    /// Subscribe to a podcast
    /// - Parameters:
    ///   - podcast: The podcast entity to subscribe to
    ///   - context: Core Data context for saving
    ///   - queueLatestEpisode: Whether to automatically queue the latest unplayed episode
    func subscribe(
        to podcast: Podcast,
        context: NSManagedObjectContext,
        queueLatestEpisode: Bool = true
    ) {
        guard let feedUrl = podcast.feedUrl?.normalizeURL() else {
            LogManager.shared.error("❌ Cannot subscribe - invalid feed URL")
            return
        }
        
        // 1. Update Core Data
        podcast.isSubscribed = true
        
        // 2. Queue latest episode if requested
        if queueLatestEpisode {
            queueLatestUnplayedEpisode(for: podcast, context: context)
        }
        
        // 3. Save Core Data changes
        do {
            try context.save()
            LogManager.shared.info("✅ Subscribed to: \(podcast.title ?? feedUrl)")
        } catch {
            LogManager.shared.error("❌ Failed to save subscription: \(error)")
            return
        }
        
        // 4. Subscribe to FCM topic
        SubscriptionSyncService.shared.subscribeToFeed(feedUrl: feedUrl)
        
        // 5. Report to backend
        SubscriptionSyncService.shared.reportFeedsToBackend()
    }
    
    /// Unsubscribe from a podcast
    /// - Parameters:
    ///   - podcast: The podcast entity to unsubscribe from
    ///   - context: Core Data context for saving
    ///   - removeEpisodes: Whether to remove episodes (keeping those with meaningful playback)
    func unsubscribe(
        from podcast: Podcast,
        context: NSManagedObjectContext,
        removeEpisodes: Bool = true
    ) {
        guard let feedUrl = podcast.feedUrl?.normalizeURL() else {
            LogManager.shared.error("❌ Cannot unsubscribe - invalid feed URL")
            return
        }
        
        // 1. Update Core Data
        podcast.isSubscribed = false
        
        // 2. Remove episodes if requested (preserves those with meaningful playback)
        if removeEpisodes {
            cleanupEpisodes(for: podcast, context: context)
        }
        
        // 3. Save Core Data changes
        do {
            try context.save()
            LogManager.shared.info("✅ Unsubscribed from: \(podcast.title ?? feedUrl)")
        } catch {
            LogManager.shared.error("❌ Failed to save unsubscription: \(error)")
            return
        }
        
        // 4. Unsubscribe from FCM topic
        SubscriptionSyncService.shared.unsubscribeFromFeed(feedUrl: feedUrl)
        
        // 5. Report to backend
        SubscriptionSyncService.shared.reportFeedsToBackend()
    }
    
    /// Subscribe to multiple podcasts (useful for OPML import or onboarding)
    /// - Parameters:
    ///   - podcasts: Array of podcast entities to subscribe to
    ///   - context: Core Data context for saving
    ///   - queueLatestEpisodes: Whether to queue latest episodes
    func subscribeBulk(
        to podcasts: [Podcast],
        context: NSManagedObjectContext,
        queueLatestEpisodes: Bool = true
    ) {
        guard !podcasts.isEmpty else { return }
        
        var successCount = 0
        var feedUrls: [String] = []
        
        // Update all podcasts and collect feed URLs
        for podcast in podcasts {
            guard let feedUrl = podcast.feedUrl?.normalizeURL() else { continue }
            
            podcast.isSubscribed = true
            feedUrls.append(feedUrl)
            
            if queueLatestEpisodes {
                queueLatestUnplayedEpisode(for: podcast, context: context)
            }
            
            successCount += 1
        }
        
        // Save Core Data changes
        do {
            try context.save()
            LogManager.shared.info("✅ Bulk subscribed to \(successCount) podcasts")
        } catch {
            LogManager.shared.error("❌ Failed to save bulk subscriptions: \(error)")
            return
        }
        
        // Subscribe to all FCM topics
        for feedUrl in feedUrls {
            SubscriptionSyncService.shared.subscribeToFeed(feedUrl: feedUrl)
        }
        
        // Report to backend once for all subscriptions
        SubscriptionSyncService.shared.reportFeedsToBackend()
    }
    
    // MARK: - Helper Functions
    
    /// Queue the latest unplayed episode for a podcast
    private func queueLatestUnplayedEpisode(for podcast: Podcast, context: NSManagedObjectContext) {
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        episodeRequest.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        episodeRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        
        do {
            let episodes = try context.fetch(episodeRequest)
            // Filter for unplayed episodes in memory (isPlayed is a computed property)
            if let latestUnplayed = episodes.first(where: { !$0.isPlayed }) {
                addToQueue(latestUnplayed)
                LogManager.shared.info("📥 Queued latest episode: \(latestUnplayed.title ?? "Unknown")")
            }
        } catch {
            LogManager.shared.error("❌ Failed to queue latest episode: \(error)")
        }
    }
    
    /// Clean up episodes when unsubscribing (preserves episodes with meaningful playback)
    private func cleanupEpisodes(for podcast: Podcast, context: NSManagedObjectContext) {
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        
        do {
            let episodes = try context.fetch(request)
            var removedCount = 0
            var preservedCount = 0
            
            for episode in episodes {
                // Check if episode has meaningful playback data
                // (same logic as AppDelegate's cleanup)
                let hasMeaningfulPlayback = episode.isPlayed ||
                                           episode.isFav ||
                                           episode.isQueued ||
                                           episode.playbackPosition > 300 // 5 minutes
                
                if hasMeaningfulPlayback {
                    // Keep the episode but remove it from queue
                    episode.isQueued = false
                    preservedCount += 1
                } else {
                    // Remove episode entirely - no meaningful interaction
                    context.delete(episode)
                    removedCount += 1
                }
            }
            
            LogManager.shared.info("🗑️ Cleaned up \(removedCount) episodes, preserved \(preservedCount) with meaningful playback")
            
        } catch {
            LogManager.shared.error("❌ Failed to cleanup episodes: \(error)")
        }
    }
}
