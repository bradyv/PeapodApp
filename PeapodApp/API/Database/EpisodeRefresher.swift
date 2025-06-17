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
    // 🚀 ENHANCED: Global refresh coordination
    private static let globalRefreshLock = NSLock()
    private static var activeRefreshes = Set<String>()
    private static let podcastRefreshLocks = NSMapTable<NSString, NSLock>.strongToStrongObjects()
    
    private static let feedCacheKey = "FeedHeaderCache"
        
    struct FeedCacheEntry: Codable {
        let lastModified: String?
        let etag: String?
        let lastChecked: Date
        let feedUrl: String
    }
    
    // 🚀 REDUCED: Lower concurrency to prevent race conditions
    private static let MAX_CONCURRENT_REFRESHES = 2
    private static let BATCH_SIZE = 50
    
    // Helper function to convert HTTP URLs to HTTPS
    private static func forceHTTPS(_ urlString: String?) -> String? {
        guard let urlString = urlString else { return nil }
        return urlString.replacingOccurrences(of: "http://", with: "https://")
    }
    
    // 🚀 NEW: Create unique episode key for deduplication
    private static func createEpisodeKey(from item: RSSFeedItem) -> String? {
        if let guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "guid:\(guid)"
        }
        if let audioUrl = forceHTTPS(item.enclosure?.attributes?.url) {
            return "audio:\(audioUrl)"
        }
        if let title = item.title, let pubDate = item.pubDate {
            return "title_date:\(title.lowercased())_\(pubDate.timeIntervalSince1970)"
        }
        return nil
    }
    
    static func refreshPodcastEpisodes(for podcast: Podcast, context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        LogManager.shared.info("🔄 Starting smart refresh for: \(podcast.title ?? "Unknown")")
        
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
        
        // 🚀 ENHANCED: Global coordination to prevent concurrent refreshes of same podcast
        globalRefreshLock.lock()
        let feedKey = httpsUrl
        if activeRefreshes.contains(feedKey) {
            globalRefreshLock.unlock()
            print("⏩ Skipping refresh for \(podcast.title ?? "podcast"), already in progress globally")
            completion?()
            return
        }
        activeRefreshes.insert(feedKey)
        globalRefreshLock.unlock()
        
        // Cleanup function
        let cleanup = {
            globalRefreshLock.lock()
            activeRefreshes.remove(feedKey)
            globalRefreshLock.unlock()
        }
        
        // Get or create podcast-specific lock
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
            cleanup()
            print("⏩ Skipping refresh for \(podcast.title ?? "podcast"), lock busy")
            completion?()
            return
        }
        
        let completionWrapper = {
            lock.unlock()
            cleanup()
            completion?()
        }
        
        // 🚀 Step 1: Check headers first
        checkFeedHeaders(url: url, podcast: podcast) { shouldRefresh, cachedEntry in
            if !shouldRefresh {
                LogManager.shared.info("⚡ \(podcast.title ?? "Podcast"): No changes detected via headers, skipping")
                completionWrapper()
                return
            }
            
            LogManager.shared.info("🔄 \(podcast.title ?? "Podcast"): Changes detected, downloading feed...")
            
            // 🚀 Step 2: Only download and parse if headers indicate changes
            downloadAndParseFeed(url: url, podcast: podcast, context: context, cacheEntry: cachedEntry, completion: completionWrapper)
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
                
                // 🚀 ENHANCED: Debug header information
                if let cachedEntry = cachedEntry {
                    print("🔍 \(podcast.title ?? "Podcast") headers:")
                    print("   Old ETag: \(cachedEntry.etag?.prefix(20) ?? "none")")
                    print("   New ETag: \(newEtag?.prefix(20) ?? "none")")
                    print("   Old Last-Modified: \(cachedEntry.lastModified ?? "none")")
                    print("   New Last-Modified: \(newLastModified ?? "none")")
                }
                
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
    
    // 🚀 ENHANCED: More intelligent header change detection
    private static func hasHeadersChanged(oldLastModified: String?, newLastModified: String?, oldEtag: String?, newEtag: String?) -> Bool {
        
        // If we have etags, compare them (most reliable)
        if let oldEtag = oldEtag, let newEtag = newEtag {
            let changed = oldEtag != newEtag
            if !changed {
                print("⚡ ETags match - no changes needed")
            }
            return changed
        }
        
        // If we have last-modified dates, try to parse and compare with tolerance
        if let oldLastModified = oldLastModified, let newLastModified = newLastModified {
            // Try multiple date formats that RSS feeds commonly use
            let formatters = [
                "EEE, dd MMM yyyy HH:mm:ss zzz",  // RFC 2822
                "yyyy-MM-dd'T'HH:mm:ss'Z'",      // ISO 8601
                "yyyy-MM-dd'T'HH:mm:sszzz",      // ISO 8601 with timezone
                "EEE, dd MMM yyyy HH:mm:ss 'GMT'", // GMT specific
                "dd MMM yyyy HH:mm:ss zzz"       // Alternative format
            ]
            
            for format in formatters {
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = Locale(identifier: "en_US_POSIX")
                
                if let oldDate = formatter.date(from: oldLastModified),
                   let newDate = formatter.date(from: newLastModified) {
                    
                    // Allow 1 minute tolerance for server timestamp variations
                    let timeDifference = abs(newDate.timeIntervalSince(oldDate))
                    let changed = timeDifference > 60 // 1 minute tolerance
                    
                    if !changed {
                        print("⚡ Last-Modified dates within tolerance (\(String(format: "%.0f", timeDifference))s) - no changes needed")
                    }
                    return changed
                }
            }
            
            // Fallback to string comparison if date parsing fails
            let changed = oldLastModified != newLastModified
            if !changed {
                print("⚡ Last-Modified strings match - no changes needed")
            }
            return changed
        }
        
        // 🚀 CONSERVATIVE: If we had cache data but now have no useful headers,
        // check how old our cache is before assuming change
        if let oldEtag = oldEtag ?? oldLastModified {
            // We had cache data - be conservative about assuming changes
            let cacheEntry = getCachedEntry(for: nil) // This will need the feedUrl passed down
            if let entry = cacheEntry,
               Date().timeIntervalSince(entry.lastChecked) < 3600 { // Less than 1 hour old
                print("⚡ Recent cache data but no server headers - assuming no changes")
                return false
            }
        }
        
        // First time or very old cache - consider it changed
        let hasNewHeaders = newLastModified != nil || newEtag != nil
        if hasNewHeaders {
            print("🔄 First time or old cache - assuming changes")
        }
        return hasNewHeaders
    }
    
    // 🚀 Download and parse feed (only called when headers indicate changes)
    private static func downloadAndParseFeed(url: URL, podcast: Podcast, context: NSManagedObjectContext, cacheEntry: FeedCacheEntry?, completion: (() -> Void)?) {
        
        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    context.perform {
                        // Update cache after successful parsing
                        if let cacheEntry = cacheEntry {
                            saveCacheEntry(cacheEntry)
                        }
                        
                        // Process episodes in batches
                        processEpisodesInBatches(
                            rss: rss,
                            podcast: podcast,
                            context: context,
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
    
    // 🚀 ENHANCED: Process episodes in batches with better duplicate prevention
    private static func processEpisodesInBatches(
        rss: RSSFeed,
        podcast: Podcast,
        context: NSManagedObjectContext,
        completion: (() -> Void)?
    ) {
        // Update podcast metadata first
        updatePodcastMetadata(rss: rss, podcast: podcast)
        
        guard let items = rss.items, !items.isEmpty else {
            PersistenceController.shared.safeSave(context: context, description: "Podcast metadata update")
            completion?()
            return
        }
        
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
                context: context
            )
            
            totalNewEpisodes += batchNewEpisodes
            
            // ✅ Save less frequently - only every 3 batches (300 episodes)
            if i % (batchSize * 3) == 0 && context.hasChanges {
                PersistenceController.shared.safeSave(context: context, description: "Episode batch \(i/batchSize)")
            }
        }
        
        // Final save only if there are changes
        if context.hasChanges {
            PersistenceController.shared.safeSave(context: context, description: "Final episode batch")
            if totalNewEpisodes > 0 {
                LogManager.shared.info("✅ \(podcast.title ?? "Podcast"): \(totalNewEpisodes) new episodes saved")
            }
        } else {
            // Add this logging to see when no changes are made
            print("ℹ️ \(podcast.title ?? "Podcast"): No changes to save")
        }
        
        completion?()
    }
    
    // 🚀 ENHANCED: Better duplicate detection using PersistenceController helpers
    private static func findExistingEpisode(
        item: RSSFeedItem,
        podcast: Podcast,
        context: NSManagedObjectContext,
        processedKeys: inout Set<String> // Track what we've already processed in this batch
    ) -> Episode? {
        
        // 🚀 NEW: Check if we've already processed this episode in current batch
        if let episodeKey = createEpisodeKey(from: item) {
            if processedKeys.contains(episodeKey) {
                print("🔄 Skipping duplicate episode in same batch: \(item.title ?? "Unknown")")
                return nil // Signal to skip this episode
            }
            processedKeys.insert(episodeKey)
        }
        
        // 🚀 ENHANCED: Use persistence controller helper for better duplicate detection
        return PersistenceController.shared.episodeExists(
            guid: item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
            audioUrl: forceHTTPS(item.enclosure?.attributes?.url),
            title: item.title,
            podcast: podcast,
            in: context
        )
    }
    
    // 🚀 ENHANCED: Process a batch of episodes with better deduplication
    private static func processBatch(
        items: [RSSFeedItem],
        podcast: Podcast,
        context: NSManagedObjectContext
    ) -> Int {
        var newEpisodesCount = 0
        var updatedEpisodesCount = 0
        var processedKeys = Set<String>() // Track processed episodes in this batch
        
        for item in items {
            guard let title = item.title else { continue }
            
            // 🚀 ENHANCED: Use improved duplicate detection
            let existingEpisode = findExistingEpisode(
                item: item,
                podcast: podcast,
                context: context,
                processedKeys: &processedKeys
            )
            
            // If findExistingEpisode returns nil but we processed the key, skip (duplicate in batch)
            if existingEpisode == nil && processedKeys.contains(createEpisodeKey(from: item) ?? "") {
                continue
            }
            
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
                
                // Queue new episodes if subscribed (on main thread to avoid race conditions)
                if podcast.isSubscribed {
                    DispatchQueue.main.async {
                        toggleQueued(episode)
                    }
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
        if podcast.image == nil {
            podcast.image = forceHTTPS(rss.image?.url) ??
                           forceHTTPS(rss.iTunes?.iTunesImage?.attributes?.href) ??
                           forceHTTPS(rss.items?.first?.iTunes?.iTunesImage?.attributes?.href)
        }
        
        if podcast.podcastDescription == nil {
            podcast.podcastDescription = rss.description ??
            rss.iTunes?.iTunesSummary ??
            rss.items?.first?.iTunes?.iTunesSummary ??
            rss.items?.first?.description
        }
    }
    
    // 🚀 ENHANCED: Use dedicated episode refresh context
    static func refreshAllSubscribedPodcasts(context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        let backgroundContext = PersistenceController.shared.episodeRefreshContext()
        
        backgroundContext.perform {
            let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
            request.predicate = NSPredicate(format: "isSubscribed == YES")
            
            guard let podcasts = try? backgroundContext.fetch(request) else {
                completion?()
                return
            }
            
            print("🔄 Smart refreshing \(podcasts.count) subscribed podcasts")
            
            // 🚀 REDUCED: Lower concurrency to prevent race conditions
            let semaphore = DispatchSemaphore(value: MAX_CONCURRENT_REFRESHES)
            let group = DispatchGroup()
            
            let startTime = Date()
            
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
                let duration = Date().timeIntervalSince(startTime)
                print("🎯 Smart refresh completed in \(String(format: "%.2f", duration))s")
                
                // 🚀 ENHANCED: Force context refresh before final save
                backgroundContext.refreshAllObjects()
                
                // 🚀 ENHANCED: Use safe save operation
                PersistenceController.shared.safeSave(context: backgroundContext, description: "Episode refresh batch")
                
                // Run deduplication after all refreshes complete
                PersistenceController.shared.performDeduplication()
                
                // 🚀 NEW: Notify main context of changes
                DispatchQueue.main.async {
                    PersistenceController.shared.container.viewContext.refreshAllObjects()
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
        
        LogManager.shared.info("🔔 Force smart refreshing for notification")
        let context = PersistenceController.shared.episodeRefreshContext()
        refreshAllSubscribedPodcasts(context: context, completion: completion)
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
