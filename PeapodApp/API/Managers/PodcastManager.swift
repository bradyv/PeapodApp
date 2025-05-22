//
//  PodcastManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-21.
//

import Foundation
import CoreData
import FeedKit

// MARK: - Podcast Management
class PodcastManager {
    
    // MARK: - Podcast Creation/Fetching
    static func fetchOrCreatePodcast(
        feedUrl: String,
        context: NSManagedObjectContext,
        title: String? = nil,
        author: String? = nil
    ) -> Podcast {
        let request = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "feedUrl == %@", feedUrl)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        } else {
            let podcast = Podcast(context: context)
            podcast.id = UUID().uuidString
            podcast.feedUrl = feedUrl
            podcast.title = title
            podcast.author = author
            podcast.isSubscribed = false
            return podcast
        }
    }
    
    // MARK: - Feed Loading and Podcast Creation
    static func loadPodcastFromFeed(
        feedUrl: String,
        context: NSManagedObjectContext,
        completion: @escaping (Podcast?) -> Void
    ) {
        guard let url = URL(string: feedUrl) else {
            completion(nil)
            return
        }

        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    context.perform {
                        let podcast = self.createOrUpdatePodcast(from: rss, feedUrl: feedUrl, context: context)
                        DispatchQueue.main.async {
                            completion(podcast)
                        }
                    }
                } else {
                    completion(nil)
                }
            case .failure(let error):
                print("❌ FeedKit error: \(error)")
                completion(nil)
            }
        }
    }
    
    // MARK: - Podcast Update from RSS
    private static func createOrUpdatePodcast(
        from rss: RSSFeed,
        feedUrl: String,
        context: NSManagedObjectContext
    ) -> Podcast {
        let podcast = fetchOrCreatePodcast(
            feedUrl: feedUrl,
            context: context,
            title: rss.title,
            author: rss.iTunes?.iTunesAuthor
        )

        // Update podcast metadata if missing
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

        // Create/update episodes
        EpisodeManager.createOrUpdateEpisodes(from: rss.items ?? [], for: podcast, context: context)

        do {
            try context.save()
        } catch {
            print("❌ Error saving podcast: \(error)")
        }
        
        return podcast
    }
}

// MARK: - Episode Management
class EpisodeManager {
    
    // MARK: - Episode Refresh with Deduplication
    static func refreshPodcastEpisodes(
        for podcast: Podcast,
        context: NSManagedObjectContext,
        completion: (() -> Void)? = nil
    ) {
        guard let feedUrl = podcast.feedUrl, let url = URL(string: feedUrl) else {
            completion?()
            return
        }
        
        // Use the existing lock mechanism from EpisodeRefresher
        let podcastId = podcast.id as NSString? ?? "unknown" as NSString
        var lock: NSLock
        
        objc_sync_enter(EpisodeRefresher.podcastRefreshLocks)
        if let existingLock = EpisodeRefresher.podcastRefreshLocks.object(forKey: podcastId) {
            lock = existingLock
        } else {
            lock = NSLock()
            EpisodeRefresher.podcastRefreshLocks.setObject(lock, forKey: podcastId)
        }
        objc_sync_exit(EpisodeRefresher.podcastRefreshLocks)
        
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
                        // Update podcast metadata
                        updatePodcastMetadata(podcast: podcast, from: rss)
                        
                        // Create/update episodes with notification handling
                        createOrUpdateEpisodes(
                            from: rss.items ?? [],
                            for: podcast,
                            context: context,
                            handleNewEpisodes: true
                        )
                        
                        do {
                            try context.save()
                            print("✅ Saved episodes for \(podcast.title ?? "Unknown")")
                        } catch {
                            print("❌ Error saving podcast refresh: \(error)")
                        }
                        
                        DispatchQueue.main.async {
                            completion?()
                        }
                    }
                } else {
                    completion?()
                }
            case .failure(let error):
                print("❌ Feed parsing error: \(error)")
                completion?()
            }
        }
    }
    
    // MARK: - Episode Creation/Update Logic
    static func createOrUpdateEpisodes(
        from items: [RSSFeedItem],
        for podcast: Podcast,
        context: NSManagedObjectContext,
        handleNewEpisodes: Bool = false
    ) {
        // Build lookup maps for efficient episode matching
        let lookupMaps = buildEpisodeLookupMaps(for: podcast, items: items, context: context)
        
        for item in items {
            guard let title = item.title else { continue }
            
            // Find existing episode using multiple strategies
            let existingEpisode = findExistingEpisode(
                for: item,
                using: lookupMaps,
                title: title
            )
            
            // Create or update episode
            let episode = existingEpisode ?? Episode(context: context)
            let isNewEpisode = existingEpisode == nil
            
            if isNewEpisode {
                episode.id = UUID().uuidString
                episode.podcast = podcast
            }
            
            // Update episode properties
            updateEpisodeProperties(episode: episode, from: item, podcast: podcast)
            
            // Handle new episode notifications and queueing
            if isNewEpisode && handleNewEpisodes && podcast.isSubscribed {
                print("📣 New episode detected: \(episode.title ?? "Unknown") — sending notification")
                sendNewEpisodeNotification(for: episode)
                
                do {
                    try context.save()
                    
                    // Queue the episode using its ID to avoid cross-context issues
                    DispatchQueue.main.async {
                        let mainContext = PersistenceController.shared.container.viewContext
                        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", episode.id ?? "")
                        fetchRequest.fetchLimit = 1
                        
                        if let mainEpisode = try? mainContext.fetch(fetchRequest).first {
                            toggleQueued(mainEpisode)
                        }
                    }
                } catch {
                    print("❌ Error saving episode before queueing: \(error)")
                }
            } else if !isNewEpisode {
                print("🧹 Existing episode updated: \(episode.title ?? "Unknown") — no notification")
            }
        }
    }
    
    // MARK: - Episode Lookup Maps
    private static func buildEpisodeLookupMaps(
        for podcast: Podcast,
        items: [RSSFeedItem],
        context: NSManagedObjectContext
    ) -> EpisodeLookupMaps {
        var guids: [String] = []
        var audioUrls: [String] = []
        var titleDateKeys: [String] = []
        
        // Collect identifiers from feed items
        for item in items {
            if let guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines) {
                guids.append(guid)
            }
            
            if let audioUrl = item.enclosure?.attributes?.url {
                audioUrls.append(audioUrl)
            }
            
            if let title = item.title, let airDate = item.pubDate {
                let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                titleDateKeys.append(key)
            }
        }
        
        // Build lookup maps
        var byGUID: [String: Episode] = [:]
        var byAudioUrl: [String: Episode] = [:]
        var byTitleDate: [String: Episode] = [:]
        
        // Fetch episodes by GUID
        if !guids.isEmpty {
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "podcast == %@ AND guid IN %@", podcast, guids)
            if let results = try? context.fetch(fetchRequest) {
                for episode in results {
                    if let guid = episode.guid?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        byGUID[guid] = episode
                    }
                }
            }
        }
        
        // Fetch episodes by audio URL
        if !audioUrls.isEmpty {
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "podcast == %@ AND audio IN %@", podcast, audioUrls)
            if let results = try? context.fetch(fetchRequest) {
                for episode in results {
                    if let audio = episode.audio {
                        byAudioUrl[audio] = episode
                    }
                }
            }
        }
        
        // Fetch episodes by title+date
        if !titleDateKeys.isEmpty {
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "podcast == %@ AND title != nil AND airDate != nil", podcast)
            if let results = try? context.fetch(fetchRequest) {
                for episode in results {
                    if let title = episode.title, let airDate = episode.airDate {
                        let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                        byTitleDate[key] = episode
                    }
                }
            }
        }
        
        return EpisodeLookupMaps(
            byGUID: byGUID,
            byAudioUrl: byAudioUrl,
            byTitleDate: byTitleDate
        )
    }
    
    // MARK: - Find Existing Episode
    private static func findExistingEpisode(
        for item: RSSFeedItem,
        using lookupMaps: EpisodeLookupMaps,
        title: String
    ) -> Episode? {
        let guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let audioUrl = item.enclosure?.attributes?.url
        let airDate = item.pubDate
        
        // Try by audio URL first (most reliable)
        if let audioUrl = audioUrl,
           let episode = lookupMaps.byAudioUrl[audioUrl] {
            return episode
        }
        
        // Then try by GUID
        if let guid = guid,
           let episode = lookupMaps.byGUID[guid] {
            return episode
        }
        
        // Finally try by title+date
        if let airDate = airDate {
            let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
            if let episode = lookupMaps.byTitleDate[key] {
                return episode
            }
        }
        
        return nil
    }
    
    // MARK: - Update Episode Properties
    private static func updateEpisodeProperties(
        episode: Episode,
        from item: RSSFeedItem,
        podcast: Podcast
    ) {
        episode.guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        episode.title = item.title
        episode.audio = item.enclosure?.attributes?.url
        episode.episodeDescription = item.content?.contentEncoded ??
                                    item.iTunes?.iTunesSummary ??
                                    item.description
        episode.airDate = item.pubDate
        
        if let durationString = item.iTunes?.iTunesDuration {
            episode.duration = Double(durationString)
        }
        
        episode.episodeImage = item.iTunes?.iTunesImage?.attributes?.href ?? podcast.image
    }
    
    // MARK: - Update Podcast Metadata
    private static func updatePodcastMetadata(podcast: Podcast, from rss: RSSFeed) {
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
    
    // MARK: - Refresh All Subscribed Podcasts
    static func refreshAllSubscribedPodcasts(
        context: NSManagedObjectContext,
        completion: (() -> Void)? = nil
    ) {
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        backgroundContext.perform {
            let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
            request.predicate = NSPredicate(format: "isSubscribed == YES")

            if let podcasts = try? backgroundContext.fetch(request) {
                let group = DispatchGroup()

                for podcast in podcasts {
                    group.enter()
                    refreshPodcastEpisodes(for: podcast, context: backgroundContext) {
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    do {
                        try backgroundContext.save()
                        print("✅ Background context saved after refreshing subscribed podcasts")
                        
                        mergeDuplicateEpisodes(context: backgroundContext)
                    } catch {
                        print("❌ Failed to save background context: \(error)")
                    }
                    completion?()
                }
            } else {
                completion?()
            }
        }
    }
}

// MARK: - Supporting Types
private struct EpisodeLookupMaps {
    let byGUID: [String: Episode]
    let byAudioUrl: [String: Episode]
    let byTitleDate: [String: Episode]
}
