//
//  EpisodeRefresher.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-04.
//

import Foundation
import CoreData
import FeedKit

class EpisodeRefresher {
    private static let podcastRefreshLocks = NSMapTable<NSString, NSLock>.strongToStrongObjects()
    
    private static let feedCacheKey = "FeedHeaderCache"
        
    struct FeedCacheEntry: Codable {
        let lastModified: String?
        let etag: String?
        let lastChecked: Date
        let feedUrl: String
    }
    
    // 🚀 Batch size to control memory usage and reduce saves
    private static let BATCH_SIZE = 50
    
    // Helper function to convert HTTP URLs to HTTPS
    private static func forceHTTPS(_ urlString: String?) -> String? {
        guard let urlString = urlString else { return nil }
        return urlString.replacingOccurrences(of: "http://", with: "https://")
    }
    
    static func refreshPodcastEpisodes(for podcast: Podcast, context: NSManagedObjectContext, limitToRecent: Bool = false, completion: (() -> Void)? = nil) {
        LogManager.shared.info("🔄 Starting smart refresh for: \(podcast.title ?? "Unknown") \(limitToRecent ? "(limited to recent episodes)" : "(full feed)")")
        
        guard let feedUrl = podcast.feedUrl else {
            LogManager.shared.error("❌ No valid feed URL for: \(podcast.title ?? "Unknown")")
            completion?()
            return
        }
        
        // Convert HTTP to HTTPS for the feed URL
        let httpsUrl = forceHTTPS(feedUrl) ?? feedUrl
        
        guard let url = URL(string: httpsUrl) else {
            LogManager.shared.error("❌ Invalid feed URL for: \(podcast.title ?? "Unknown")")
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
        
        // Skip header check if we're doing a full refresh (limitToRecent = false)
        // This ensures we always fetch the complete feed when explicitly requested
        if limitToRecent {
            // 🚀 Step 1: Check headers first
            checkFeedHeaders(url: url, podcast: podcast) { shouldRefresh, cachedEntry in
                if !shouldRefresh {
                    LogManager.shared.info("⚡ \(podcast.title ?? "Podcast"): No changes detected via headers, skipping")
                    completion?()
                    return
                }
                
                LogManager.shared.info("🔄 \(podcast.title ?? "Podcast"): Changes detected, downloading feed...")
                
                // 🚀 Step 2: Only download and parse if headers indicate changes
                downloadAndParseFeed(url: url, podcast: podcast, context: context, cacheEntry: cachedEntry, limitToRecent: limitToRecent, completion: completion)
            }
        } else {
            // Force full refresh without header checks
            downloadAndParseFeed(url: url, podcast: podcast, context: context, cacheEntry: nil, limitToRecent: limitToRecent, completion: completion)
        }
    }
    
    static func loadInitialEpisodes(for podcast: Podcast, context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        LogManager.shared.info("🆕 Loading initial episodes (limited to 25) for: \(podcast.title ?? "Unknown")")
        
        guard let feedUrl = podcast.feedUrl else {
            LogManager.shared.error("❌ No valid feed URL for: \(podcast.title ?? "Unknown")")
            completion?()
            return
        }
        
        let httpsUrl = forceHTTPS(feedUrl) ?? feedUrl
        
        guard let url = URL(string: httpsUrl) else {
            LogManager.shared.error("❌ Invalid feed URL for: \(podcast.title ?? "Unknown")")
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
            print("⏩ Skipping initial load for \(podcast.title ?? "podcast"), already in progress")
            completion?()
            return
        }
        
        defer { lock.unlock() }
        
        // Force download without header checks, with strict limiting for initial load
        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    context.perform {
                        // Process episodes with strict limiting for initial load
                        processEpisodesInBatches(
                            rss: rss,
                            podcast: podcast,
                            context: context,
                            limitToRecent: true, // FORCE limiting for initial load
                            completion: {
                                LogManager.shared.info("✅ Completed initial load for: \(podcast.title ?? "Unknown")")
                                completion?()
                            }
                        )
                    }
                } else {
                    completion?()
                }
            case .failure(let error):
                LogManager.shared.error("❌ Failed to parse feed for initial load \(podcast.title ?? "podcast"): \(error)")
                completion?()
            }
        }
    }
    
    private static func checkFeedHeaders(url: URL, podcast: Podcast, completion: @escaping (Bool, FeedCacheEntry?) -> Void) {
        
        // Get cached data for this feed
        let cachedEntry = getCachedEntry(for: podcast.feedUrl)
        
        // Create HEAD request
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Peapod/2.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        // Add conditional headers if we have cache data
        if let etag = cachedEntry?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = cachedEntry?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                guard let httpResponse = response as? HTTPURLResponse else {
                    // If HEAD request fails, assume we should refresh
                    LogManager.shared.warning("⚠️ HEAD request failed for \(podcast.title ?? "podcast"), will refresh anyway")
                    completion(true, cachedEntry)
                    return
                }
                
                let statusCode = httpResponse.statusCode
                
                // 304 Not Modified = no changes
                if statusCode == 304 {
                    print("⚡ \(podcast.title ?? "Podcast"): 304 Not Modified")
                    updateCacheEntry(for: podcast.feedUrl, lastModified: cachedEntry?.lastModified, etag: cachedEntry?.etag)
                    completion(false, cachedEntry)
                    return
                }
                
                // Extract new headers
                let newLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
                let newEtag = httpResponse.value(forHTTPHeaderField: "ETag")
                
                // Check if anything actually changed
                let hasChanges = hasHeadersChanged(
                    oldLastModified: cachedEntry?.lastModified,
                    newLastModified: newLastModified,
                    oldEtag: cachedEntry?.etag,
                    newEtag: newEtag
                )
                
                if hasChanges {
                    print("🔄 \(podcast.title ?? "Podcast"): Headers indicate changes")
                    let updatedEntry = FeedCacheEntry(
                        lastModified: newLastModified,
                        etag: newEtag,
                        lastChecked: Date(),
                        feedUrl: podcast.feedUrl ?? ""
                    )
                    completion(true, updatedEntry)
                } else {
                    print("⚡ \(podcast.title ?? "Podcast"): Headers unchanged")
                    updateCacheEntry(for: podcast.feedUrl, lastModified: newLastModified, etag: newEtag)
                    completion(false, cachedEntry)
                }
            }
        }
        
        task.resume()
    }
    
    // 🚀 Helper to check if headers changed
    private static func hasHeadersChanged(oldLastModified: String?, newLastModified: String?, oldEtag: String?, newEtag: String?) -> Bool {
        
        // If we have etags, compare them
        if let oldEtag = oldEtag, let newEtag = newEtag {
            return oldEtag != newEtag
        }
        
        // If we have last-modified dates, compare them
        if let oldLastModified = oldLastModified, let newLastModified = newLastModified {
            return oldLastModified != newLastModified
        }
        
        // If we only have new headers (first time), consider it changed
        if newLastModified != nil || newEtag != nil {
            return true
        }
        
        // No useful headers = assume changed (safer)
        return true
    }
    
    // 🚀 Download and parse feed (only called when headers indicate changes or forced)
    private static func downloadAndParseFeed(url: URL, podcast: Podcast, context: NSManagedObjectContext, cacheEntry: FeedCacheEntry?, limitToRecent: Bool, completion: (() -> Void)?) {
        
        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    context.perform {
                        // Update cache after successful parsing (only if we have cache entry)
                        if let cacheEntry = cacheEntry {
                            saveCacheEntry(cacheEntry)
                        }
                        
                        // Process episodes in batches with limit option
                        processEpisodesInBatches(
                            rss: rss,
                            podcast: podcast,
                            context: context,
                            limitToRecent: limitToRecent,
                            completion: {
                                LogManager.shared.info("✅ Completed refresh for: \(podcast.title ?? "Unknown")")
                                completion?()
                            }
                        )
                    }
                } else {
                    completion?()
                }
            case .failure(let error):
                LogManager.shared.error("❌ Failed to parse feed for \(podcast.title ?? "podcast"): \(error)")
                completion?()
            }
        }
    }
    
    // 🚀 Cache management
    private static func getCachedEntry(for feedUrl: String?) -> FeedCacheEntry? {
        guard let feedUrl = feedUrl else { return nil }
        
        guard let data = UserDefaults.standard.data(forKey: "\(feedCacheKey)_\(feedUrl.hashValue)"),
              let entry = try? JSONDecoder().decode(FeedCacheEntry.self, from: data) else {
            return nil
        }
        
        // Return cached entry if it's less than 5 minutes old for optimization
        let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)
        return entry.lastChecked > fiveMinutesAgo ? entry : nil
    }
    
    private static func saveCacheEntry(_ entry: FeedCacheEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: "\(feedCacheKey)_\(entry.feedUrl.hashValue)")
    }
    
    private static func updateCacheEntry(for feedUrl: String?, lastModified: String?, etag: String?) {
        guard let feedUrl = feedUrl else { return }
        
        let entry = FeedCacheEntry(
            lastModified: lastModified,
            etag: etag,
            lastChecked: Date(),
            feedUrl: feedUrl
        )
        saveCacheEntry(entry)
    }
    
    // 🚀 MODIFIED: Process episodes in batches with optional limit
    private static func processEpisodesInBatches(
        rss: RSSFeed,
        podcast: Podcast,
        context: NSManagedObjectContext,
        limitToRecent: Bool = false,
        completion: (() -> Void)?
    ) {
        // Update podcast metadata first
        updatePodcastMetadata(rss: rss, podcast: podcast)
        
        guard let items = rss.items, !items.isEmpty else {
            saveContextIfNeeded(context: context)
            completion?()
            return
        }
        
        // 🆕 Limit episodes to most recent 50 if requested
        let episodesToProcess = limitToRecent ? Array(items.prefix(25)) : items
        
        if limitToRecent {
            LogManager.shared.info("📦 Processing recent \(episodesToProcess.count) episodes out of \(items.count) total for: \(podcast.title ?? "Unknown")")
        }
        
        // 🚀 Pre-fetch all existing episodes to avoid repeated database queries
        let existingEpisodes = fetchAllExistingEpisodes(for: podcast, context: context)
        
        var totalNewEpisodes = 0
        let totalItems = episodesToProcess.count
        
        // Process items in larger batches to reduce save frequency
        let batchSize = 100 // Increased from 50
        
        for i in stride(from: 0, to: totalItems, by: batchSize) {
            let endIndex = min(i + batchSize, totalItems)
            let batch = Array(episodesToProcess[i..<endIndex])
            
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
                    LogManager.shared.info("✅ \(podcast.title ?? "Podcast"): \(totalNewEpisodes) new episodes saved")
                }
            } catch {
                LogManager.shared.error("❌ Error saving podcast refresh: \(error)")
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
        fetchRequest.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        
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
            LogManager.shared.error("❌ Error fetching existing episodes: \(error)")
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
        let audioUrl = forceHTTPS(item.enclosure?.attributes?.url)
        let airDate = item.pubDate
        
        // Strategy 1: Match by audio URL (most reliable)
        if let audioUrl = audioUrl {
            if let existing = existingEpisodes[audioUrl] {
                return existing
            }
        }
        
        // Strategy 2: Match by GUID
        if let guid = guid {
            if let existing = existingEpisodes[guid] {
                return existing
            }
        }
        
        // Strategy 3: Match by title + air date
        if let title = title, let airDate = airDate {
            let titleDateKey = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
            if let existing = existingEpisodes[titleDateKey] {
                return existing
            }
        }
        
        // Strategy 4: FALLBACK - Direct database query using podcastId
        if let guid = guid {
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "guid == %@ AND podcastId == %@", guid, podcast.id ?? "")
            fetchRequest.fetchLimit = 1
            
            if let existing = try? context.fetch(fetchRequest).first {
                return existing
            }
        }
        
        // Strategy 5: LAST RESORT - Match by title alone using podcastId
        if let title = title {
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "title == %@ AND podcastId == %@", title, podcast.id ?? "")
            fetchRequest.fetchLimit = 1
            
            if let existing = try? context.fetch(fetchRequest).first {
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
        context: NSManagedObjectContext,
        skipQueueing: Bool = false // 🆕 Add parameter to skip queueing old episodes
    ) -> Int {
        var newEpisodesCount = 0
        var updatedEpisodesCount = 0
        var newestNewEpisode: Episode? = nil
        var newestAirDate: Date? = nil
        
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
                episode.podcastId = podcast.id
                updateEpisodeAttributes(episode: episode, item: item, podcast: podcast)
                episode.id = episode.guid?.trimmingCharacters(in: .whitespacesAndNewlines)
                newEpisodesCount += 1
                
                print("🆕 Created new episode: \(title)")
                
                // 🆕 Track the newest episode by air date
                if podcast.isSubscribed && !skipQueueing {
                    if let airDate = item.pubDate {
                        if newestAirDate == nil || airDate > newestAirDate! {
                            newestAirDate = airDate
                            newestNewEpisode = episode
                        }
                    } else if newestNewEpisode == nil {
                        // If no air date, use the first episode as fallback
                        newestNewEpisode = episode
                    }
                }
            }
        }
        
        // 🆕 Only queue the newest episode (if subscribed and not skipping)
        if let newestEpisode = newestNewEpisode {
            newestEpisode.isQueued = true
            LogManager.shared.info("📥 Queued newest episode: \(newestEpisode.title ?? "Unknown")")
        }
        
        // ✅ Only log summary if there were actual changes
        if newEpisodesCount > 0 || updatedEpisodesCount > 0 {
            print("📊 \(podcast.title ?? "Podcast"): \(newEpisodesCount) new, \(updatedEpisodesCount) updated")
            if let newestEpisode = newestNewEpisode {
                print("📥 Queued newest: \(newestEpisode.title ?? "Unknown")")
            }
        }
        
        return newEpisodesCount
    }

    private static func hasEpisodeChanged(episode: Episode, item: RSSFeedItem, podcast: Podcast) -> Bool {
        let newGuid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = item.title
        let newAudio = forceHTTPS(item.enclosure?.attributes?.url) // Convert to HTTPS
        let newDescription = item.content?.contentEncoded ?? item.iTunes?.iTunesSummary ?? item.description
        let newAirDate = item.pubDate
        let newDuration = item.iTunes?.iTunesDuration ?? 0
        let newEpisodeImage = forceHTTPS(item.iTunes?.iTunesImage?.attributes?.href) ?? podcast.image // Convert to HTTPS
        
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
        episode.audio = forceHTTPS(item.enclosure?.attributes?.url) // Convert to HTTPS
        episode.episodeDescription = item.content?.contentEncoded ?? item.iTunes?.iTunesSummary ?? item.description
        episode.airDate = item.pubDate
        
        if let duration = item.iTunes?.iTunesDuration {
            episode.duration = duration
        }
        
        episode.episodeImage = forceHTTPS(item.iTunes?.iTunesImage?.attributes?.href) ?? podcast.image // Convert to HTTPS
    }
    
    // 🚀 Update podcast metadata separately
    private static func updatePodcastMetadata(rss: RSSFeed, podcast: Podcast) {
        // Always check for updated artwork
        let newArtworkUrl = forceHTTPS(rss.image?.url) ??
                           forceHTTPS(rss.iTunes?.iTunesImage?.attributes?.href) ??
                           forceHTTPS(rss.items?.first?.iTunes?.iTunesImage?.attributes?.href)
        
        if let newUrl = newArtworkUrl, newUrl != podcast.image {
            LogManager.shared.info("🎨 Updated artwork for \(podcast.title ?? "podcast"): \(newUrl)")
            podcast.image = newUrl
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
            LogManager.shared.error("❌ Error saving context during batch processing: \(error)")
        }
    }
    
    // 🚀 Optimized refresh all with better concurrency control
    static func refreshAllSubscribedPodcasts(context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
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
            
            print("🔄 Smart refreshing \(podcasts.count) subscribed podcasts")
            
            let semaphore = DispatchSemaphore(value: 3) // Slightly higher since HEAD requests are faster
            let group = DispatchGroup()
            var refreshedCount = 0
            var skippedCount = 0
            
            let startTime = Date()
            
            for podcast in podcasts {
                group.enter()
                
                DispatchQueue.global(qos: .utility).async {
                    semaphore.wait()
                    
                    // Use limitToRecent: true for regular background refreshes
                    refreshPodcastEpisodes(for: podcast, context: backgroundContext, limitToRecent: true) {
                        // Track if we actually refreshed or skipped
                        // This would need to be passed back from refreshPodcastEpisodes if you want exact counts
                        semaphore.signal()
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .global(qos: .utility)) {
                let duration = Date().timeIntervalSince(startTime)
                print("🎯 Smart refresh completed in \(String(format: "%.2f", duration))s")
                
                // Final save and cleanup
                do {
                    if backgroundContext.hasChanges {
                        try backgroundContext.save()
                        LogManager.shared.info("✅ Background context saved after smart refresh")
                    } else {
                        print("ℹ️ No background context changes to save")
                    }
                    
                    // Run deduplication less frequently
                    mergeDuplicateEpisodes(context: backgroundContext)
                    
                } catch {
                    LogManager.shared.error("❌ Failed to save background context: \(error)")
                }
                
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }
    }
    
    static func loadNextBatchOfEpisodes(
        for podcast: Podcast,
        context: NSManagedObjectContext,
        completion: @escaping (Int, Bool) -> Void // (newEpisodesAdded, hasMoreToLoad)
    ) {
        LogManager.shared.info("📦 Loading next batch for: \(podcast.title ?? "Unknown")")
        
        guard let feedUrl = podcast.feedUrl else {
            LogManager.shared.error("❌ No valid feed URL for: \(podcast.title ?? "Unknown")")
            completion(0, false)
            return
        }
        
        let httpsUrl = forceHTTPS(feedUrl) ?? feedUrl
        
        guard let url = URL(string: httpsUrl) else {
            LogManager.shared.error("❌ Invalid feed URL for: \(podcast.title ?? "Unknown")")
            completion(0, false)
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
            print("⏩ Skipping batch load for \(podcast.title ?? "podcast"), already in progress")
            completion(0, false)
            return
        }
        
        defer { lock.unlock() }
        
        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    context.perform {
                        processNextBatchByGUID(
                            rss: rss,
                            podcast: podcast,
                            context: context,
                            completion: completion
                        )
                    }
                } else {
                    completion(0, false)
                }
            case .failure(let error):
                LogManager.shared.error("❌ Failed to parse feed for batch load \(podcast.title ?? "podcast"): \(error)")
                completion(0, false)
            }
        }
    }

    // 🆕 Process next batch by excluding already-loaded GUIDs
    private static func processNextBatchByGUID(
        rss: RSSFeed,
        podcast: Podcast,
        context: NSManagedObjectContext,
        completion: @escaping (Int, Bool) -> Void
    ) {
        guard let items = rss.items, !items.isEmpty else {
            completion(0, false)
            return
        }
        
        // Get all currently loaded episodes for this podcast using podcastId
        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        
        let existingEpisodes = (try? context.fetch(fetchRequest)) ?? []
        let loadedGUIDs = Set(existingEpisodes.compactMap { $0.guid?.trimmingCharacters(in: .whitespacesAndNewlines) })
        let loadedAudioURLs = Set(existingEpisodes.compactMap { $0.audio })
        
        LogManager.shared.info("📊 Current episodes: \(existingEpisodes.count), Total available: \(items.count)")
        LogManager.shared.info("🔑 Loaded GUIDs: \(loadedGUIDs.count), Loaded audio URLs: \(loadedAudioURLs.count)")
        
        // Filter items to only those we haven't loaded yet
        let unloadedItems = items.filter { item in
            // Check GUID first (most reliable)
            if let guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return !loadedGUIDs.contains(guid)
            }
            
            // Fallback: check audio URL if no GUID
            if let audioURL = forceHTTPS(item.enclosure?.attributes?.url) {
                return !loadedAudioURLs.contains(audioURL)
            }
            
            // If no GUID or audio URL, consider it unloaded (rare case)
            return true
        }
        
        // Take the next 50 episodes
        let batchItems = Array(unloadedItems.prefix(50))
        
        guard !batchItems.isEmpty else {
            LogManager.shared.info("✅ No more episodes to load for \(podcast.title ?? "podcast")")
            completion(0, false)
            return
        }
        
        LogManager.shared.info("📦 Processing next \(batchItems.count) unloaded episodes")
        
        // Pre-fetch existing episodes for duplicate checking
        let existingEpisodeMap = fetchAllExistingEpisodes(for: podcast, context: context)
        
        // Process the batch
        let newEpisodesCount = processBatch(
            items: batchItems,
            podcast: podcast,
            existingEpisodes: existingEpisodeMap,
            context: context,
            skipQueueing: true
        )
        
        // Save changes
        if context.hasChanges {
            saveContextIfNeeded(context: context)
        }
        
        // Check if there are more episodes to load
        let hasMore = unloadedItems.count > batchItems.count
        
        LogManager.shared.info("✅ Loaded \(newEpisodesCount) new episodes. Has more: \(hasMore)")
        completion(newEpisodesCount, hasMore)
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
        
        LogManager.shared.info("🔔 Force smart refreshing for notification")
        let context = PersistenceController.shared.container.newBackgroundContext()
        refreshAllSubscribedPodcasts(context: context, completion: completion)
    }

    // 🆕 NEW METHOD: Fetch all remaining episodes for a podcast
    static func fetchAllRemainingEpisodes(for podcast: Podcast, context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        LogManager.shared.info("📚 Fetching all remaining episodes for: \(podcast.title ?? "Unknown")")
        
        // Force a full refresh without header checks and without limiting episodes
        refreshPodcastEpisodes(for: podcast, context: context, limitToRecent: false, completion: completion)
    }
}

extension EpisodeRefresher {
    static func cleanupOldCacheEntries() {
        let userDefaults = UserDefaults.standard
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        let cacheKeys = allKeys.filter { $0.hasPrefix(feedCacheKey) }
        let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        for key in cacheKeys {
            if let data = userDefaults.data(forKey: key),
               let entry = try? JSONDecoder().decode(FeedCacheEntry.self, from: data),
               entry.lastChecked < oneWeekAgo {
                userDefaults.removeObject(forKey: key)
            }
        }
    }
}
