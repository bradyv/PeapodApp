//
//  EpisodeRefresher.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-04.
//

import Foundation
import CoreData
import FeedKit

class EpisodeRefresher {
    private static let podcastRefreshLocks = NSMapTable<NSString, NSLock>.strongToStrongObjects()
    
    // 🚀 Batch size to control memory usage and reduce saves
    private static let BATCH_SIZE = 50
    
    static func refreshPodcastEpisodes(for podcast: Podcast, context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        print("🔄 Starting refresh for: \(podcast.title ?? "Unknown")")
            
        guard let feedUrl = podcast.feedUrl, let url = URL(string: feedUrl) else {
            print("❌ No valid feed URL for: \(podcast.title ?? "Unknown")")
            completion?()
            return
        }
        
        let podcastId = podcast.id as NSString? ?? "unknown" as NSString
        var lock: NSLock
        
        objc_sync_enter(podcastRefreshLocks)
        if let existingLock = podcastRefreshLocks.object(forKey: podcastId) {
            lock = existingLock
        } else {
            lock = NSLock()
            podcastRefreshLocks.setObject(lock, forKey: podcastId)
        }
        objc_sync_exit(podcastRefreshLocks)
        
        guard lock.try() else {
            print("⏩ Skipping refresh for \(podcast.title ?? "podcast"), already in progress")
            completion?()
            return
        }
        
        defer { lock.unlock() }
        
        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    context.perform {
                        // 🚀 Process episodes in batches to reduce memory pressure
                        processEpisodesInBatches(
                            rss: rss,
                            podcast: podcast,
                            context: context,
                            completion: {
                                print("✅ Completed refresh for: \(podcast.title ?? "Unknown")")
                                completion?()
                            }
                        )
                    }
                } else {
                    completion?()
                }
            case .failure:
                completion?()
            }
        }
    }
    
    // 🚀 NEW: Process episodes in batches to reduce memory usage and saves
    private static func processEpisodesInBatches(
        rss: RSSFeed,
        podcast: Podcast,
        context: NSManagedObjectContext,
        completion: (() -> Void)?
    ) {
        // Update podcast metadata first
        updatePodcastMetadata(rss: rss, podcast: podcast)
        
        guard let items = rss.items, !items.isEmpty else {
            saveContextIfNeeded(context: context)
            completion?()
            return
        }
        
        // 🚀 Pre-fetch all existing episodes to avoid repeated database queries
        let existingEpisodes = fetchAllExistingEpisodes(for: podcast, context: context)
        
        var totalNewEpisodes = 0
        let totalItems = items.count
        
        // Process items in larger batches to reduce save frequency
        let batchSize = 100 // Increased from 50
        
        for i in stride(from: 0, to: totalItems, by: batchSize) {
            let endIndex = min(i + batchSize, totalItems)
            let batch = Array(items[i..<endIndex])
            
            let batchNewEpisodes = processBatch(
                items: batch,
                podcast: podcast,
                existingEpisodes: existingEpisodes,
                context: context
            )
            
            totalNewEpisodes += batchNewEpisodes
            
            // ✅ Save less frequently - only every 3 batches (300 episodes)
            if i % (batchSize * 3) == 0 && context.hasChanges {
                saveContextIfNeeded(context: context)
            }
        }
        
        // Final save only if there are changes
        if context.hasChanges {
            do {
                try context.save()
                if totalNewEpisodes > 0 {
                    print("✅ \(podcast.title ?? "Podcast"): \(totalNewEpisodes) new episodes saved")
                }
            } catch {
                print("❌ Error saving podcast refresh: \(error)")
            }
        } else {
            // Add this logging to see when no changes are made
            print("ℹ️ \(podcast.title ?? "Podcast"): No changes to save")
        }
        
        completion?()
    }
    
    // 🚀 Pre-fetch all existing episodes to avoid repeated queries
    private static func fetchAllExistingEpisodes(
        for podcast: Podcast,
        context: NSManagedObjectContext
    ) -> [String: Episode] {
        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "podcast == %@", podcast)
        
        var episodeMap: [String: Episode] = [:]
        
        do {
            let episodes = try context.fetch(fetchRequest)
            for episode in episodes {
                // Create lookup keys for different matching strategies
                if let guid = episode.guid?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    episodeMap[guid] = episode
                }
                if let audioUrl = episode.audio {
                    episodeMap[audioUrl] = episode
                }
                if let title = episode.title, let airDate = episode.airDate {
                    let titleDateKey = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                    episodeMap[titleDateKey] = episode
                }
            }
        } catch {
            print("❌ Error fetching existing episodes: \(error)")
        }
        
        return episodeMap
    }
    
    private static func findExistingEpisode(
        item: RSSFeedItem,
        podcast: Podcast,
        existingEpisodes: [String: Episode],
        context: NSManagedObjectContext
    ) -> Episode? {
        
        let title = item.title
        let guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let audioUrl = item.enclosure?.attributes?.url
        let airDate = item.pubDate
        
        // Strategy 1: Match by audio URL (most reliable)
        if let audioUrl = audioUrl {
            if let existing = existingEpisodes[audioUrl] {
//                print("🎯 Found existing episode by audio URL: \(existing.title ?? "Unknown")")
                return existing
            }
        }
        
        // Strategy 2: Match by GUID
        if let guid = guid {
            if let existing = existingEpisodes[guid] {
//                print("🎯 Found existing episode by GUID: \(existing.title ?? "Unknown")")
                return existing
            }
        }
        
        // Strategy 3: Match by title + air date
        if let title = title, let airDate = airDate {
            let titleDateKey = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
            if let existing = existingEpisodes[titleDateKey] {
//                print("🎯 Found existing episode by title+date: \(existing.title ?? "Unknown")")
                return existing
            }
        }
        
        // Strategy 4: FALLBACK - Direct database query for extra safety
        // This catches cases where the pre-fetch might have missed something
        if let guid = guid {
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "guid == %@ AND podcast == %@", guid, podcast)
            fetchRequest.fetchLimit = 1
            
            if let existing = try? context.fetch(fetchRequest).first {
//                print("🎯 Found existing episode via fallback database query: \(existing.title ?? "Unknown")")
                return existing
            }
        }
        
        // Strategy 5: LAST RESORT - Match by title alone (for episodes with inconsistent GUIDs)
        if let title = title {
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "title == %@ AND podcast == %@", title, podcast)
            fetchRequest.fetchLimit = 1
            
            if let existing = try? context.fetch(fetchRequest).first {
//                print("🎯 Found existing episode by title match: \(existing.title ?? "Unknown")")
                return existing
            }
        }
        
        return nil
    }
    
    // 🚀 Process a batch of episodes
    private static func processBatch(
        items: [RSSFeedItem],
        podcast: Podcast,
        existingEpisodes: [String: Episode],
        context: NSManagedObjectContext
    ) -> Int {
        var newEpisodesCount = 0
        var updatedEpisodesCount = 0
        
        for item in items {
            guard let title = item.title else { continue }
            
            // Use enhanced duplicate detection
            let existingEpisode = findExistingEpisode(
                item: item,
                podcast: podcast,
                existingEpisodes: existingEpisodes,
                context: context
            )
            
            if let existing = existingEpisode {
                // ✅ Only update if something actually changed
                if hasEpisodeChanged(episode: existing, item: item, podcast: podcast) {
                    updateEpisodeAttributes(episode: existing, item: item, podcast: podcast)
                    updatedEpisodesCount += 1
                    print("📝 Updated episode: \(title)")
                }
                // ✅ No logging for unchanged episodes
            } else {
                // Create new episode
                let episode = Episode(context: context)
                episode.id = UUID().uuidString
                episode.podcast = podcast
                updateEpisodeAttributes(episode: episode, item: item, podcast: podcast)
                newEpisodesCount += 1
                
                print("🆕 Created new episode: \(title)")
                
                // Queue new episodes if subscribed
                if podcast.isSubscribed {
                    toggleQueued(episode)
                }
            }
        }
        
        // ✅ Only log summary if there were actual changes
        if newEpisodesCount > 0 || updatedEpisodesCount > 0 {
            print("📊 \(podcast.title ?? "Podcast"): \(newEpisodesCount) new, \(updatedEpisodesCount) updated")
        }
        
        return newEpisodesCount
    }
    
    private static func hasEpisodeChanged(episode: Episode, item: RSSFeedItem, podcast: Podcast) -> Bool {
        let newGuid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = item.title
        let newAudio = item.enclosure?.attributes?.url
        let newDescription = item.content?.contentEncoded ?? item.iTunes?.iTunesSummary ?? item.description
        let newAirDate = item.pubDate
        let newDuration = item.iTunes?.iTunesDuration ?? 0
        let newEpisodeImage = item.iTunes?.iTunesImage?.attributes?.href ?? podcast.image
        
        // Compare each field - only return true if something actually changed
        return episode.guid != newGuid ||
               episode.title != newTitle ||
               episode.audio != newAudio ||
               episode.episodeDescription != newDescription ||
               episode.airDate != newAirDate ||
               (newDuration > 0 && abs(episode.duration - newDuration) > 1.0) || // Allow 1 second tolerance
               episode.episodeImage != newEpisodeImage
    }
    
    // 🚀 Separate method to update episode attributes
    private static func updateEpisodeAttributes(episode: Episode, item: RSSFeedItem, podcast: Podcast) {
        episode.guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        episode.title = item.title
        episode.audio = item.enclosure?.attributes?.url
        episode.episodeDescription = item.content?.contentEncoded ?? item.iTunes?.iTunesSummary ?? item.description
        episode.airDate = item.pubDate
        
        if let duration = item.iTunes?.iTunesDuration {
            episode.duration = duration
        }
        
        episode.episodeImage = item.iTunes?.iTunesImage?.attributes?.href ?? podcast.image
    }
    
    // 🚀 Update podcast metadata separately
    private static func updatePodcastMetadata(rss: RSSFeed, podcast: Podcast) {
        if podcast.image == nil {
            podcast.image = rss.image?.url ??
            rss.iTunes?.iTunesImage?.attributes?.href ??
            rss.items?.first?.iTunes?.iTunesImage?.attributes?.href
        }
        
        if podcast.podcastDescription == nil {
            podcast.podcastDescription = rss.description ??
            rss.iTunes?.iTunesSummary ??
            rss.items?.first?.iTunes?.iTunesSummary ??
            rss.items?.first?.description
        }
    }
    
    // 🚀 Helper to save context with error handling
    private static func saveContextIfNeeded(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            print("❌ Error saving context during batch processing: \(error)")
        }
    }
    
    // 🚀 Optimized refresh all with better concurrency control
    static func refreshAllSubscribedPodcasts(context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        // ✅ Add global refresh throttling
        let lastRefreshKey = "lastGlobalRefresh"
        let now = Date()
        let lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date ?? Date.distantPast
        
        // Don't refresh if we refreshed less than 2 minutes ago
        if now.timeIntervalSince(lastRefresh) < 120 {
            print("⏩ Skipping refresh - too recent (\(Int(now.timeIntervalSince(lastRefresh)))s ago)")
            completion?()
            return
        }
        
        UserDefaults.standard.set(now, forKey: lastRefreshKey)
        
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.stalenessInterval = 0.0
        
        backgroundContext.perform {
            let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
            request.predicate = NSPredicate(format: "isSubscribed == YES")
            
            guard let podcasts = try? backgroundContext.fetch(request) else {
                completion?()
                return
            }
            
            print("🔄 Refreshing \(podcasts.count) subscribed podcasts")
            
            // 🚀 Limit concurrent operations to prevent overwhelming the system
            let semaphore = DispatchSemaphore(value: 2) // Reduced from 3 to 2
            let group = DispatchGroup()
            
            for podcast in podcasts {
                group.enter()
                
                DispatchQueue.global(qos: .utility).async {
                    semaphore.wait()
                    
                    refreshPodcastEpisodes(for: podcast, context: backgroundContext) {
                        semaphore.signal()
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .global(qos: .utility)) {
                print("🎯 All podcast refreshes completed")
                
                // Final save and cleanup
                do {
                    if backgroundContext.hasChanges {
                        try backgroundContext.save()
                        print("✅ Background context saved after podcast refresh")
                    } else {
                        print("ℹ️ No background context changes to save (all episodes up-to-date)")
                    }
                    
                    // Run deduplication even less frequently
                    if Int.random(in: 1...10) == 1 { // Only 10% of the time
                        mergeDuplicateEpisodes(context: backgroundContext)
                    }
                    
                } catch {
                    print("❌ Failed to save background context: \(error)")
                }
                
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }
    }
    
    // 🆕 Force refresh for push notifications - restored method
    static func forceRefreshForNotification(completion: (() -> Void)? = nil) {
        let lastNotificationRefreshKey = "lastNotificationRefresh"
        let now = Date()
        let lastRefresh = UserDefaults.standard.object(forKey: lastNotificationRefreshKey) as? Date ?? Date.distantPast
        
        // Don't refresh if we refreshed less than 1 minute ago for notifications
        if now.timeIntervalSince(lastRefresh) < 60 {
            print("⏩ Skipping notification refresh - too recent")
            completion?()
            return
        }
        
        UserDefaults.standard.set(now, forKey: lastNotificationRefreshKey)
        
        print("🔔 Force refreshing for notification")
        let context = PersistenceController.shared.container.newBackgroundContext()
        refreshAllSubscribedPodcasts(context: context, completion: completion)
    }
}
