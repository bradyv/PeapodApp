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

    static func refreshPodcastEpisodes(for podcast: Podcast, context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        guard let feedUrl = podcast.feedUrl, let url = URL(string: feedUrl) else {
            completion?()
            return
        }
        
        // Get or create a lock for this specific podcast
        let podcastId = podcast.id as NSString? ?? "unknown" as NSString
        var lock: NSLock
        
        // Thread-safe access to the locks map
        objc_sync_enter(podcastRefreshLocks)
        if let existingLock = podcastRefreshLocks.object(forKey: podcastId) {
            lock = existingLock
        } else {
            lock = NSLock()
            podcastRefreshLocks.setObject(lock, forKey: podcastId)
        }
        objc_sync_exit(podcastRefreshLocks)
        
        // Try to acquire the lock, otherwise skip this refresh
        guard lock.try() else {
            print("⏩ Skipping refresh for \(podcast.title ?? "podcast"), already in progress")
            completion?()
            return
        }
        
        // Make sure to release the lock when done
        defer { lock.unlock() }
        
        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    context.perform {
                        // Update podcast metadata
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
                        
                        // Build GUID and audio URL lists for better matching
                        var guids: [String] = []
                        var audioUrls: [String] = []
                        var titleDateKeys: [String] = []
                        
                        // First pass: collect all identifiers
                        for item in rss.items ?? [] {
                            if let guid = item.guid?.value {
                                // Normalize GUID to prevent case/whitespace issues
                                let normalizedGuid = guid.trimmingCharacters(in: .whitespacesAndNewlines)
                                guids.append(normalizedGuid)
                            }
                            
                            if let audioUrl = item.enclosure?.attributes?.url {
                                audioUrls.append(audioUrl)
                            }
                            
                            if let title = item.title, let airDate = item.pubDate {
                                let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                                titleDateKeys.append(key)
                            }
                        }
                        
                        // Maps for quick lookups
                        var existingEpisodesByGUID: [String: Episode] = [:]
                        var existingEpisodesByAudioUrl: [String: Episode] = [:]
                        var existingEpisodesByTitleDate: [String: Episode] = [:]
                        
                        // Fetch episodes by GUID
                        if !guids.isEmpty {
                            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                            fetchRequest.predicate = NSPredicate(format: "podcast == %@ AND guid IN %@", podcast, guids)
                            if let results = try? context.fetch(fetchRequest) {
                                for episode in results {
                                    if let guid = episode.guid?.trimmingCharacters(in: .whitespacesAndNewlines) {
                                        existingEpisodesByGUID[guid] = episode
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
                                        existingEpisodesByAudioUrl[audio] = episode
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
                                        existingEpisodesByTitleDate[key] = episode
                                    }
                                }
                            }
                        }
                        
                        var newEpisodesAdded = 0
                        
                        // Process episodes
                        for item in rss.items ?? [] {
                            guard let title = item.title else { continue }
                            
                            let guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
                            let audioUrl = item.enclosure?.attributes?.url
                            let airDate = item.pubDate
                            
                            // Try to find existing episode using all available identifiers
                            var existingEpisode: Episode?
                            
                            // First try by audio URL (most reliable)
                            if let audioUrl = audioUrl {
                                existingEpisode = existingEpisodesByAudioUrl[audioUrl]
                            }
                            
                            // Then try by GUID if audio URL didn't match
                            if existingEpisode == nil, let guid = guid {
                                existingEpisode = existingEpisodesByGUID[guid]
                            }
                            
                            // Finally try by title+date as last resort
                            if existingEpisode == nil, let airDate = airDate {
                                let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                                existingEpisode = existingEpisodesByTitleDate[key]
                            }
                            
                            // Create or update episode
                            let episode = existingEpisode ?? Episode(context: context)
                            
                            if existingEpisode == nil {
                                episode.id = UUID().uuidString
                                episode.podcast = podcast
                                newEpisodesAdded += 1
                            }
                            
                            // Update episode attributes
                            episode.guid = guid
                            episode.title = title
                            episode.audio = audioUrl
                            episode.episodeDescription = item.content?.contentEncoded ?? item.iTunes?.iTunesSummary ?? item.description
                            episode.airDate = airDate
                            if let durationString = item.iTunes?.iTunesDuration {
                                episode.duration = Double(durationString)
                            }
                            episode.episodeImage = item.iTunes?.iTunesImage?.attributes?.href ?? podcast.image
                            
                            // Handle new episodes: queue them if subscribed
                            if existingEpisode == nil, podcast.isSubscribed {
                                print("🆕 New episode detected in app: \(episode.title ?? "Unknown")")
                                toggleQueued(episode)
                            } else if existingEpisode != nil {
//                                print("🧹 Existing episode updated: \(episode.title ?? "Unknown")")
                            }
                        }
                        
                        // Save changes
                        do {
                            try context.save()
                            if newEpisodesAdded > 0 {
                                print("✅ Saved episodes for \(podcast.title ?? "Unknown") - \(newEpisodesAdded) new episodes added")
                            } else {
                                print("✅ Saved episodes for \(podcast.title ?? "Unknown")")
                            }
                            completion?()
                        } catch {
                            print("❌ Error saving podcast refresh: \(error)")
                            completion?()
                        }
                    }
                } else {
                    completion?()
                }
            case .failure:
                completion?()
            }
        }
    }

    static func refreshAllSubscribedPodcasts(context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        // 🚀 Create a new background context
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
    
    // 🆕 NEW: Force refresh for push notifications
    static func forceRefreshForNotification(completion: (() -> Void)? = nil) {
        print("🔔 Force refreshing all subscribed podcasts due to push notification")
        let context = PersistenceController.shared.container.newBackgroundContext()
        refreshAllSubscribedPodcasts(context: context, completion: completion)
    }
}
