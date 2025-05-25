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
        guard let feedUrl = podcast.feedUrl, let url = URL(string: feedUrl) else {
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
                            completion: completion
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
        
        var newEpisodesCount = 0
        let totalItems = items.count
        
        // Process items in batches
        for i in stride(from: 0, to: totalItems, by: BATCH_SIZE) {
            let endIndex = min(i + BATCH_SIZE, totalItems)
            let batch = Array(items[i..<endIndex])
            
            let batchNewEpisodes = processBatch(
                items: batch,
                podcast: podcast,
                existingEpisodes: existingEpisodes,
                context: context
            )
            
            newEpisodesCount += batchNewEpisodes
            
            // 🚀 Save every few batches to prevent memory buildup
            if i % (BATCH_SIZE * 3) == 0 {
                saveContextIfNeeded(context: context)
            }
        }
        
        // Final save
        do {
            try context.save()
            if newEpisodesCount > 0 {
                print("✅ Saved episodes for \(podcast.title ?? "Unknown") - \(newEpisodesCount) new episodes added")
            }
        } catch {
            print("❌ Error saving podcast refresh: \(error)")
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
    
    // 🚀 Process a batch of episodes
    private static func processBatch(
        items: [RSSFeedItem],
        podcast: Podcast,
        existingEpisodes: [String: Episode],
        context: NSManagedObjectContext
    ) -> Int {
        var newEpisodesCount = 0
        
        for item in items {
            guard let title = item.title else { continue }
            
            let guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            let audioUrl = item.enclosure?.attributes?.url
            let airDate = item.pubDate
            
            // Try to find existing episode
            var existingEpisode: Episode?
            
            if let audioUrl = audioUrl {
                existingEpisode = existingEpisodes[audioUrl]
            }
            if existingEpisode == nil, let guid = guid {
                existingEpisode = existingEpisodes[guid]
            }
            if existingEpisode == nil, let airDate = airDate {
                let titleDateKey = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                existingEpisode = existingEpisodes[titleDateKey]
            }
            
            // Create or update episode
            let episode = existingEpisode ?? Episode(context: context)
            
            if existingEpisode == nil {
                episode.id = UUID().uuidString
                episode.podcast = podcast
                newEpisodesCount += 1
                
                // Queue new episodes if subscribed
                if podcast.isSubscribed {
                    toggleQueued(episode)
                }
            }
            
            // Update episode attributes
            updateEpisodeAttributes(episode: episode, item: item, podcast: podcast)
        }
        
        return newEpisodesCount
    }
    
    // 🚀 Separate method to update episode attributes
    private static func updateEpisodeAttributes(episode: Episode, item: RSSFeedItem, podcast: Podcast) {
        episode.guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        episode.title = item.title
        episode.audio = item.enclosure?.attributes?.url
        episode.episodeDescription = item.content?.contentEncoded ?? item.iTunes?.iTunesSummary ?? item.description
        episode.airDate = item.pubDate
        
        if let durationString = item.iTunes?.iTunesDuration {
            episode.duration = Double(durationString)
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
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // 🚀 Set a reasonable timeout for operations
        backgroundContext.stalenessInterval = 0.0
        
        backgroundContext.perform {
            let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
            request.predicate = NSPredicate(format: "isSubscribed == YES")
            
            guard let podcasts = try? backgroundContext.fetch(request) else {
                completion?()
                return
            }
            
            // 🚀 Limit concurrent operations to prevent overwhelming the system
            let semaphore = DispatchSemaphore(value: 3) // Max 3 concurrent refreshes
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
                // Final save and cleanup
                do {
                    if backgroundContext.hasChanges {
                        try backgroundContext.save()
                        print("✅ Background context saved after refreshing subscribed podcasts")
                    }
                    
                    // Run deduplication less frequently
                    if Bool.random() { // Only 50% of the time
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
        print("🔔 Force refreshing all subscribed podcasts due to push notification")
        let context = PersistenceController.shared.container.newBackgroundContext()
        refreshAllSubscribedPodcasts(context: context, completion: completion)
    }
}
