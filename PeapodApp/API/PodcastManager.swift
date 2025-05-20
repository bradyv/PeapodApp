//
//  PodcastManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-19.
//

//
//  PodcastManager.swift
//  PeapodApp
//
//  Created for Brady Valentino on 2025-05-19.
//

import Foundation
import CoreData
import FeedKit
import Combine
import BackgroundTasks
import UserNotifications

/// A singleton manager class that centralizes all podcast and episode related operations
final class PodcastManager {
    // MARK: - Singleton
    static let shared = PodcastManager()
    
    // MARK: - Properties
    private let backgroundContext: NSManagedObjectContext
    private let refreshLock = NSLock()
    private var refreshTasks: [String: Task<Void, Error>] = [:]
    private var activeFeedParsers: [String: FeedParser] = [:]
    
    // MARK: - Initialization
    private init() {
        // Create a dedicated background context for all operations
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = PersistenceController.shared.container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.backgroundContext = context
        
        // Perform initial setup
        registerBackgroundTasks()
    }
    
    // MARK: - Background Task Registration
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.bradyv.Peapod.Dev.refreshEpisodes.v1", using: nil) { [weak self] task in
            print("🚀 BGTask fired: com.bradyv.Peapod.Dev.refreshEpisodes.v1")
            self?.handleEpisodeRefresh(task: task as! BGAppRefreshTask)
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.bradyv.Peapod.Dev.deleteOldEpisodes.v1", using: nil) { [weak self] task in
            print("🚀 BGTask fired: com.bradyv.Peapod.Dev.deleteOldEpisodes.v1")
            self?.handleOldEpisodeCleanup(task: task as! BGAppRefreshTask)
        }
        
        scheduleEpisodeRefresh()
        scheduleEpisodeCleanup()
    }
    
    // MARK: - Podcast Discovery
    
    /// Fetch the top podcasts from iTunes API
    func fetchTopPodcasts(limit: Int = 21) async throws -> [PodcastResult] {
        return await withCheckedContinuation { continuation in
            PodcastAPI.fetchTopPodcasts(limit: limit) { results in
                continuation.resume(returning: results)
            }
        }
    }
    
    /// Search for podcasts using the iTunes API
    func searchPodcasts(query: String) async throws -> [PodcastResult] {
        guard !query.isEmpty else { return [] }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?media=podcast&entity=podcast&term=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "PodcastManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid search URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        
        return response.results
    }
    
    // MARK: - Podcast Subscription Management
    
    /// Subscribe to a podcast using its feed URL
    func subscribeToPodcast(feedUrl: String, title: String? = nil, author: String? = nil) async throws -> Podcast {
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let podcast = self.fetchOrCreatePodcast(feedUrl: feedUrl, title: title, author: author)
                    podcast.isSubscribed = true
                    
                    // Save changes
                    try self.backgroundContext.save()
                    
                    // Merge changes to main context
                    self.mergeToMainContext()
                    
                    // Refresh episodes in the background
                    self.refreshPodcastEpisodes(for: podcast)
                    
                    continuation.resume(returning: podcast)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Unsubscribe from a podcast
    func unsubscribeFromPodcast(_ podcast: Podcast) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    // Get the podcast in our background context
                    let podcastID = podcast.objectID
                    guard let bgPodcast = try? self.backgroundContext.existingObject(with: podcastID) as? Podcast else {
                        throw NSError(domain: "PodcastManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Podcast not found in context"])
                    }
                    
                    // Update subscription status
                    bgPodcast.isSubscribed = false
                    
                    // Save changes
                    try self.backgroundContext.save()
                    
                    // Merge changes to main context
                    self.mergeToMainContext()
                    
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Episode Refreshing
    
    /// Refresh episodes for all subscribed podcasts
    func refreshAllSubscribedPodcasts(completion: (() -> Void)? = nil) {
        Task {
            // Ensure we're not already refreshing
            guard refreshLock.try() else {
                print("⏩ Skipping global refresh, already in progress")
                completion?()
                return
            }
            
            // Make sure to release the lock when done
            defer { refreshLock.unlock() }
            
            await withCheckedContinuation { continuation in
                backgroundContext.perform {
                    let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
                    request.predicate = NSPredicate(format: "isSubscribed == YES")
                    
                    do {
                        let podcasts = try self.backgroundContext.fetch(request)
                        let group = DispatchGroup()
                        
                        for podcast in podcasts {
                            group.enter()
                            self.refreshPodcastEpisodes(for: podcast) {
                                group.leave()
                            }
                        }
                        
                        group.notify(queue: .main) {
                            // Clean up potential duplicates
                            self.mergeDuplicateEpisodes()
                            
                            // Done refreshing all podcasts
                            continuation.resume(returning: ())
                            completion?()
                        }
                    } catch {
                        print("❌ Error fetching podcasts for refresh: \(error)")
                        continuation.resume(returning: ())
                        completion?()
                    }
                }
            }
        }
    }
    
    /// Refresh episodes for a specific podcast
    func refreshPodcastEpisodes(for podcast: Podcast, completion: (() -> Void)? = nil) {
        guard let feedUrl = podcast.feedUrl, let url = URL(string: feedUrl) else {
            completion?()
            return
        }
        
        // Get podcast ID for task tracking
        let podcastId = podcast.id ?? UUID().uuidString
        
        // Cancel any existing refresh task for this podcast
        if let existingTask = refreshTasks[podcastId] {
            existingTask.cancel()
            refreshTasks.removeValue(forKey: podcastId)
        }
        
        // Create a new task for refreshing this podcast
        let task: Task<Void, Error> = Task {
            do {
                try await self.performPodcastRefresh(podcast: podcast, url: url)
                
                // Remove task from tracking dictionary
                self.refreshTasks.removeValue(forKey: podcastId)
                
                // Notify completion on main thread
                DispatchQueue.main.async {
                    completion?()
                }
            } catch {
                print("❌ Error refreshing podcast: \(error)")
                
                // Remove task from tracking dictionary
                self.refreshTasks.removeValue(forKey: podcastId)
                
                // Notify completion on main thread
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }
        
        // Store the task for potential cancellation
        refreshTasks[podcastId] = task
    }
    
    private func performPodcastRefresh(podcast: Podcast, url: URL) async throws {
        // Store the parser for potential cancellation
        let parser = FeedParser(URL: url)
        let podcastId = podcast.id ?? UUID().uuidString
        activeFeedParsers[podcastId] = parser
        
        defer {
            // Clean up parser reference
            activeFeedParsers.removeValue(forKey: podcastId)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            parser.parseAsync { result in
                switch result {
                case .success(let feed):
                    if let rss = feed.rssFeed {
                        self.backgroundContext.perform {
                            do {
                                // Get the podcast in our background context
                                let podcastID = podcast.objectID
                                guard let bgPodcast = try? self.backgroundContext.existingObject(with: podcastID) as? Podcast else {
                                    continuation.resume(throwing: NSError(domain: "PodcastManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Podcast not found in context"]))
                                    return
                                }
                                
                                // Update podcast metadata
                                if bgPodcast.image == nil {
                                    bgPodcast.image = rss.image?.url ??
                                        rss.iTunes?.iTunesImage?.attributes?.href ??
                                        rss.items?.first?.iTunes?.iTunesImage?.attributes?.href
                                }
                                
                                if bgPodcast.podcastDescription == nil {
                                    bgPodcast.podcastDescription = rss.description ??
                                        rss.iTunes?.iTunesSummary ??
                                        rss.items?.first?.iTunes?.iTunesSummary ??
                                        rss.items?.first?.description
                                }
                                
                                // Process the RSS feed items to update episodes
                                let createdEpisodes = self.processRSSItems(rss.items ?? [], for: bgPodcast)
                                
                                // Save changes
                                try self.backgroundContext.save()
                                
                                // Merge changes to main context
                                self.mergeToMainContext()
                                
                                // Notify for new episodes if subscribed
                                if bgPodcast.isSubscribed {
                                    for episode in createdEpisodes {
                                        self.sendNewEpisodeNotification(for: episode)
                                        
                                        // Add to queue if auto-queue is enabled (hardcoded true for now)
                                        // In a full implementation, this would check user preferences
                                        self.addToQueue(episode)
                                    }
                                }
                                
                                continuation.resume(returning: ())
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    } else {
                        continuation.resume(throwing: NSError(domain: "PodcastManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid RSS feed format"]))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func processRSSItems(_ items: [RSSFeedItem], for podcast: Podcast) -> [Episode] {
        var newEpisodes: [Episode] = []
        
        // Build GUID and audio URL lists for better matching
        var guids: [String] = []
        var audioUrls: [String] = []
        var titleDateKeys: [String] = []
        
        // First pass: collect all identifiers
        for item in items {
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
            if let results = try? backgroundContext.fetch(fetchRequest) {
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
            if let results = try? backgroundContext.fetch(fetchRequest) {
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
            if let results = try? backgroundContext.fetch(fetchRequest) {
                for episode in results {
                    if let title = episode.title, let airDate = episode.airDate {
                        let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                        existingEpisodesByTitleDate[key] = episode
                    }
                }
            }
        }
        
        // Process episodes
        for item in items {
            guard let title = item.title else { continue }
            
            let guid = item.guid?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            let audioUrl = item.enclosure?.attributes?.url
            let airDate = item.pubDate
            
            // Try to find existing episode using all available identifiers
            var existingEpisode: Episode?
            
            // First try by GUID (most reliable)
            if let guid = guid {
                existingEpisode = existingEpisodesByGUID[guid]
            }
            
            // Then try by audio URL if GUID didn't match
            if existingEpisode == nil, let audioUrl = audioUrl {
                existingEpisode = existingEpisodesByAudioUrl[audioUrl]
            }
            
            // Finally try by title+date as last resort
            if existingEpisode == nil, let airDate = airDate {
                let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                existingEpisode = existingEpisodesByTitleDate[key]
            }
            
            // Create or update episode
            let episode = existingEpisode ?? Episode(context: backgroundContext)
            
            // For new episodes
            if existingEpisode == nil {
                episode.id = UUID().uuidString
                episode.podcast = podcast
                
                // Add to the new episodes list for notifications and queueing
                newEpisodes.append(episode)
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
        }
        
        return newEpisodes
    }
    
    // MARK: - Background Task Handlers
    
    private func handleEpisodeRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh before starting work
        scheduleEpisodeRefresh()
        
        Task {
            await refreshAllSubscribedPodcasts {
                task.setTaskCompleted(success: true)
            }
        }
    }
    
    private func handleOldEpisodeCleanup(task: BGAppRefreshTask) {
        // Schedule the next cleanup before starting work
        scheduleEpisodeCleanup()
        
        backgroundContext.perform {
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "(podcast = nil OR podcast.isSubscribed != YES) AND isSaved == NO AND isPlayed == NO")
            
            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                
                for episode in results {
                    self.backgroundContext.delete(episode)
                }
                
                try self.backgroundContext.save()
                self.mergeToMainContext()
                
                print("✅ Cleaned up \(results.count) old episodes")
                task.setTaskCompleted(success: true)
            } catch {
                print("❌ Background cleanup failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    // MARK: - Queue Management
    
    /// Add an episode to the queue
    func addToQueue(_ episode: Episode) {
        // Forward to QueueManager
        Task { @MainActor in
            QueueManager.shared.toggle(episode)
        }
    }
    
    /// Add an episode to the front of the queue (usually when starting playback)
    func addToFrontOfQueue(_ episode: Episode, pushingBack current: Episode? = nil) {
        // Forward to QueueManager
        Task { @MainActor in
            QueueManager.shared.addToFront(episode, pushingBack: current)
        }
    }
    
    // MARK: - Background Task Scheduling
    
    func scheduleEpisodeRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.bradyv.Peapod.Dev.refreshEpisodes.v1")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Scheduled background episode refresh")
            print("⏲️ Next episode refresh: \(request.earliestBeginDate!)")
        } catch {
            print("❌ Could not schedule background episode refresh: \(error)")
        }
    }
    
    func scheduleEpisodeCleanup() {
        let request = BGAppRefreshTaskRequest(identifier: "com.bradyv.Peapod.Dev.deleteOldEpisodes.v1")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 24 * 7) // 1 week
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Scheduled background episode cleanup")
        } catch {
            print("❌ Could not schedule episode cleanup task: \(error)")
        }
    }
    
    // MARK: - Notification Management
    
    /// Send notification for a new episode
    private func sendNewEpisodeNotification(for episode: Episode) {
        guard let title = episode.podcast?.title else { return }
        guard let subtitle = episode.title else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = parseHtml(episode.episodeDescription ?? "New episode available!")
        content.sound = .default
        content.userInfo = ["episodeID": episode.id ?? ""]
        
        // If artwork exists, try to attach it
        if let imageUrlString = episode.podcast?.image,
           let imageUrl = URL(string: imageUrlString) {
            
            // Download the image asynchronously
            downloadImageAndAttach(from: imageUrl, content: content) { request in
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ Failed to schedule notification: \(error.localizedDescription)")
                    } else {
                        print("✅ Notification sent for \(title)")
                    }
                }
            }
        } else {
            // No artwork, send notification immediately
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Failed to schedule notification: \(error.localizedDescription)")
                } else {
                    print("✅ Notification sent for \(title)")
                }
            }
        }
    }
    
    private func downloadImageAndAttach(from url: URL, content: UNMutableNotificationContent, completion: @escaping (UNNotificationRequest) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { tempFileUrl, response, error in
            guard let tempFileUrl = tempFileUrl else {
                completion(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                return
            }
            
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let uniqueName = UUID().uuidString + "." + ext
            let localUrl = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName)
            
            do {
                try FileManager.default.moveItem(at: tempFileUrl, to: localUrl)
                
                let attachment = try UNNotificationAttachment(identifier: "episodeImage", url: localUrl)
                content.attachments = [attachment]
            } catch {
                print("❌ Could not attach image to notification: \(error.localizedDescription)")
            }
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            completion(request)
        }
        task.resume()
    }
    
    // MARK: - Duplicate Management
    
    func mergeDuplicateEpisodes() {
        backgroundContext.perform {
            let request: NSFetchRequest<Episode> = Episode.fetchRequest()
            
            do {
                let episodes = try self.backgroundContext.fetch(request)
                print("🔎 Checking \(episodes.count) episodes for duplicates")
                
                var episodesByGUID: [String: [Episode]] = [:]
                
                for episode in episodes {
                    if let guid = episode.guid {
                        episodesByGUID[guid, default: []].append(episode)
                    }
                }
                
                var duplicatesFound = 0
                
                for (_, duplicates) in episodesByGUID {
                    if duplicates.count > 1 {
                        // Keep the newest one based on airDate
                        let sorted = duplicates.sorted {
                            ($0.airDate ?? Date.distantPast) > ($1.airDate ?? Date.distantPast)
                        }
                        
                        guard let keeper = sorted.first else { continue }
                        let toDelete = sorted.dropFirst()
                        
                        for duplicate in toDelete {
                            // Transfer important flags if they exist
                            if duplicate.isQueued { keeper.isQueued = true }
                            if duplicate.isSaved { keeper.isSaved = true }
                            if duplicate.isPlayed { keeper.isPlayed = true }
                            if duplicate.nowPlaying { keeper.nowPlaying = true }
                            
                            if duplicate.queuePosition > keeper.queuePosition {
                                keeper.queuePosition = duplicate.queuePosition
                            }
                            if duplicate.playbackPosition > 0 {
                                keeper.playbackPosition = max(keeper.playbackPosition, duplicate.playbackPosition)
                            }
                            if let playedDate = duplicate.playedDate {
                                if let existingDate = keeper.playedDate {
                                    keeper.playedDate = max(existingDate, playedDate)
                                } else {
                                    keeper.playedDate = playedDate
                                }
                            }
                            
                            // Transfer playlist relationships if needed
                            if keeper.playlist == nil, let duplicatePlaylist = duplicate.playlist {
                                keeper.playlist = duplicatePlaylist
                            }
                            
                            self.backgroundContext.delete(duplicate)
                            duplicatesFound += 1
                        }
                    }
                }
                
                if duplicatesFound > 0 {
                    try self.backgroundContext.save()
                    self.mergeToMainContext()
                    print("✅ Merged and deleted \(duplicatesFound) duplicate episode(s)")
                }
            } catch {
                print("❌ Failed merging duplicates: \(error)")
            }
        }
    }
    
    // MARK: - Debug Methods
    
    /// Manually trigger cleanup of old episodes (for testing)
    func debugPurgeOldEpisodes() {
        backgroundContext.perform {
            print("🧪 DEBUG: Starting old episode purge")
            
            let request: NSFetchRequest<Episode> = Episode.fetchRequest()
            request.predicate = NSPredicate(format: "(podcast == nil OR podcast.isSubscribed == NO) AND isSaved == NO AND isPlayed == NO")
            
            do {
                let episodes = try self.backgroundContext.fetch(request)
                print("→ Found \(episodes.count) episode(s) eligible for deletion")
                
                for episode in episodes {
                    let title = episode.title ?? "Untitled"
                    let podcast = episode.podcast?.title ?? "nil"
                    print("   - Deleting: \(title) from \(podcast)")
                    self.backgroundContext.delete(episode)
                }
                
                try self.backgroundContext.save()
                self.mergeToMainContext()
                print("✅ DEBUG: Deleted \(episodes.count) episode(s)")
            } catch {
                print("❌ DEBUG purge failed: \(error)")
            }
        }
    }
    
    // MARK: - Utility Methods
    
    /// Fetch an existing podcast or create a new one
    private func fetchOrCreatePodcast(feedUrl: String, context: NSManagedObjectContext? = nil, title: String? = nil, author: String? = nil) -> Podcast {
        let ctx = context ?? backgroundContext
        
        let request = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "feedUrl == %@", feedUrl)
        request.fetchLimit = 1
        
        if let existing = try? ctx.fetch(request).first {
            return existing
        } else {
            let podcast = Podcast(context: ctx)
            podcast.feedUrl = feedUrl
            podcast.id = UUID().uuidString
            podcast.title = title
            podcast.author = author
            return podcast
        }
    }
    
    /// Merge changes from background context to main context
    private func mergeToMainContext() {
        DispatchQueue.main.async {
            // Refresh any objects that might have changed
            PersistenceController.shared.container.viewContext.refreshAllObjects()
            do {
                try PersistenceController.shared.container.viewContext.save()
            } catch {
                print("❌ Failed to merge changes to main context: \(error)")
            }
        }
    }
}

// MARK: - Helper Extensions

extension Notification.Name {
    static let didTapEpisodeNotification = Notification.Name("didTapEpisodeNotification")
}

/// HTML parser - copied from existing code
private func parseHtml(_ html: String) -> String {
    // Simple implementation for now
    return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
}
