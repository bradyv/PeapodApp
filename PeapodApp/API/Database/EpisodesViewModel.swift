//
//  EpisodesViewModel.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-28.
//

import SwiftUI
import CoreData

@MainActor
final class EpisodesViewModel: NSObject, ObservableObject {
    @Published var queue: [Episode] = []
    @Published var latest: [Episode] = []
    @Published var unplayed: [Episode] = []
    @Published var favs: [Episode] = []
    @Published var old: [Episode] = []
    
    // Add loading state properties
    @Published var isLoading: Bool = true
    @Published var hasLoadedInitialData: Bool = false

    var context: NSManagedObjectContext?

    override init() {
        super.init()
    }

    static func placeholder() -> EpisodesViewModel {
        EpisodesViewModel()
    }

    func setup(context: NSManagedObjectContext) {
        self.context = context
        
        // Set loading state at the beginning
        isLoading = true
        
        // Load all episode lists using new boolean-based approach
        loadInitialData()
        
        // Set up observers for Core Data changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
        
        // 🔥 NEW: Listen for queue updates from AudioPlayerManager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queueDidUpdate),
            name: .episodeQueueUpdated,
            object: nil
        )
    }
    
    // New method to load initial data and track loading state
    private func loadInitialData() {
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchQueueAsync() }
                group.addTask { await self.fetchLatestAsync() }
                group.addTask { await self.fetchUnplayedAsync() }
                group.addTask { await self.fetchFavsAsync() }
                group.addTask { await self.fetchOldAsync() }
            }
            
            // Mark as loaded when all initial fetches are complete
            self.isLoading = false
            self.hasLoadedInitialData = true
        }
    }
    
    @objc private func contextDidSave() {
        // Don't set loading state for context saves (these are updates, not initial loads)
        Task { @MainActor in
            fetchQueue()
            fetchLatest()
            fetchUnplayed()
            fetchFavs()
            fetchOld()
        }
    }
    
    // 🔥 NEW: Handle queue updates from AudioPlayerManager
    @objc private func queueDidUpdate() {
        Task { @MainActor in
            fetchQueue()
        }
    }

    // MARK: - Fetch Functions (Updated to use boolean approach)

    func fetchQueue() {
        guard let context = context else { return }
        
        // For queue updates during animations, we need immediate synchronous updates
        let episodes = getQueuedEpisodes(context: context)
        self.queue = episodes
    }
    
    // 🔥 NEW: Async version for background updates - now returns async
    func fetchQueueAsync() async {
        guard let context = context else { return }
        
        // Perform Core Data operation on background thread, then update UI on main thread
        let result: [Episode] = await withCheckedContinuation { continuation in
            context.perform {
                let episodes = getQueuedEpisodes(context: context)
                continuation.resume(returning: episodes)
            }
        }
        
        // Update @Published property on main thread
        self.queue = result
    }
    
    func fetchLatest() {
        Task {
            await fetchLatestAsync()
        }
    }
    
    // Make this async and reusable
    func fetchLatestAsync() async {
        guard let context = context else { return }
        
        let result: [Episode] = await withCheckedContinuation { continuation in
            context.perform {
                // Get subscribed podcast IDs first
                let subscribedPodcastIds = getSubscribedPodcastIds(context: context)
                guard !subscribedPodcastIds.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                
                let request: NSFetchRequest<Episode> = Episode.fetchRequest()
                request.predicate = NSPredicate(format: "podcastId IN %@", subscribedPodcastIds)
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
                request.fetchLimit = 100
                
                do {
                    let episodes = try context.fetch(request)
                    continuation.resume(returning: episodes)
                } catch {
                    LogManager.shared.error("⚠️ Failed to fetch latest episodes: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
        
        await MainActor.run {
            self.latest = result
        }
    }
    
    func fetchUnplayed() {
        Task {
            await fetchUnplayedAsync()
        }
    }
    
    func fetchUnplayedAsync() async {
        guard let context = context else { return }
        
        let result: [Episode] = await withCheckedContinuation { continuation in
            context.perform {
                // Get subscribed podcast IDs first
                let subscribedPodcastIds = getSubscribedPodcastIds(context: context)
                guard !subscribedPodcastIds.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                
                // Get played episode IDs using boolean approach
                let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
                playbackRequest.predicate = NSPredicate(format: "isPlayed == YES")
                let playedPlaybackStates = (try? context.fetch(playbackRequest)) ?? []
                let playedIds = playedPlaybackStates.compactMap { $0.episodeId }
                
                let request: NSFetchRequest<Episode> = Episode.fetchRequest()
                let subscribedPredicate = NSPredicate(format: "podcastId IN %@", subscribedPodcastIds)
                
                if playedIds.isEmpty {
                    // No played episodes, so all subscribed episodes are unplayed
                    request.predicate = subscribedPredicate
                } else {
                    // Exclude played episodes
                    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                        subscribedPredicate,
                        NSPredicate(format: "NOT (id IN %@)", playedIds)
                    ])
                }
                
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
                request.fetchLimit = 100
                
                do {
                    let allEpisodes = try context.fetch(request)
                    // Also filter out episodes that have playback progress
                    let unplayedEpisodes = allEpisodes.filter { $0.playbackPosition == 0 }
                    continuation.resume(returning: unplayedEpisodes)
                } catch {
                    LogManager.shared.error("⚠️ Failed to fetch unplayed episodes: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
        
        await MainActor.run {
            self.unplayed = result
        }
    }
    
    func fetchFavs() {
        Task {
            await fetchFavsAsync()
        }
    }
    
    func fetchFavsAsync() async {
        guard let context = context else { return }
        
        let result: [Episode] = await withCheckedContinuation { continuation in
            context.perform {
                let episodes = getFavoriteEpisodes(context: context)
                continuation.resume(returning: episodes)
            }
        }
        
        await MainActor.run {
            self.favs = result
        }
    }

    func fetchOld() {
        Task {
            await fetchOldAsync()
        }
    }
    
    func fetchOldAsync() async {
        guard let context = context else { return }
        
        let result: [Episode] = await withCheckedContinuation { continuation in
            context.perform {
                // Get unsubscribed podcast IDs first
                let unsubscribedPodcastIds = getUnsubscribedPodcastIds(context: context)
                guard !unsubscribedPodcastIds.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                
                // Get all episode IDs that have ANY playback state (queued, played, or favorited)
                let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
                playbackRequest.predicate = NSPredicate(format: "isQueued == YES OR isPlayed == YES OR isFav == YES")
                let savedPlaybackStates = (try? context.fetch(playbackRequest)) ?? []
                let savedEpisodeIds = savedPlaybackStates.compactMap { $0.episodeId }
                
                let request: NSFetchRequest<Episode> = Episode.fetchRequest()
                let unsubscribedPredicate = NSPredicate(format: "podcastId IN %@", unsubscribedPodcastIds)
                
                if savedEpisodeIds.isEmpty {
                    request.predicate = unsubscribedPredicate
                } else {
                    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                        unsubscribedPredicate,
                        NSPredicate(format: "NOT (id IN %@)", savedEpisodeIds)
                    ])
                }
                
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.id, ascending: true)]
                request.fetchLimit = 100
                
                do {
                    let episodes = try context.fetch(request)
                    continuation.resume(returning: episodes)
                } catch {
                    LogManager.shared.error("⚠️ Failed to fetch old episodes: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
        
        await MainActor.run {
            self.old = result
        }
    }

    func fetchAll() {
        fetchQueue()
        fetchLatest()
        fetchUnplayed()
        fetchFavs()
        fetchOld()
    }

    func refreshEpisodes() {
        guard let context = context else { return }
        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
            // Refresh all lists after episode refresh
            Task { @MainActor in
                self.fetchAll()
            }
        }
    }

    func updateQueue() {
        Task {
            await fetchQueueAsync() // Use async version for background updates
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
