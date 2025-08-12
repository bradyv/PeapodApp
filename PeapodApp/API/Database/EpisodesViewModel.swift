//
//  EpisodesViewModel.swift
//  PeapodApp
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

    var context: NSManagedObjectContext?

    override init() {
        super.init()
    }

    static func placeholder() -> EpisodesViewModel {
        EpisodesViewModel()
    }

    func setup(context: NSManagedObjectContext) {
        self.context = context
        
        // Load all episode lists using new boolean-based approach
        fetchQueue()
        fetchLatest()
        fetchUnplayed()
        fetchFavs()
        fetchOld()
        
        // Set up observers for Core Data changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
            
        // Listen for episode refresh completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(episodeRefreshCompleted),
            name: .episodeRefreshCompleted,
            object: nil
        )
    }
    
    @objc private func contextDidSave() {
        // Refresh all lists when Core Data changes
        fetchQueue()
        fetchLatest()
        fetchUnplayed()
        fetchFavs()
        fetchOld()
    }

    // MARK: - Fetch Functions (Updated to use boolean approach)

    func fetchQueue() {
        guard let context = context else { return }
        queue = getQueuedEpisodes(context: context)
    }
    
    func fetchLatest() {
        guard let context = context else { return }
        
        // Get subscribed podcast IDs first
        let subscribedPodcastIds = getSubscribedPodcastIds(context: context)
        guard !subscribedPodcastIds.isEmpty else {
            latest = []
            return
        }
        
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId IN %@", subscribedPodcastIds)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchLimit = 100
        
        do {
            latest = try context.fetch(request)
        } catch {
            LogManager.shared.error("❌ Failed to fetch latest episodes: \(error)")
            latest = []
        }
    }
    
    func fetchUnplayed() {
        guard let context = context else { return }
        
        // Get subscribed podcast IDs first
        let subscribedPodcastIds = getSubscribedPodcastIds(context: context)
        guard !subscribedPodcastIds.isEmpty else {
            unplayed = []
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
            unplayed = allEpisodes.filter { $0.playbackPosition == 0 }
        } catch {
            LogManager.shared.error("❌ Failed to fetch unplayed episodes: \(error)")
            unplayed = []
        }
    }
    
    func fetchFavs() {
        guard let context = context else { return }
        favs = getFavoriteEpisodes(context: context)
    }

    func fetchOld() {
        guard let context = context else { return }
        
        // Get unsubscribed podcast IDs first
        let unsubscribedPodcastIds = getUnsubscribedPodcastIds(context: context)
        guard !unsubscribedPodcastIds.isEmpty else {
            old = []
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
            old = try context.fetch(request)
        } catch {
            LogManager.shared.error("❌ Failed to fetch old episodes: \(error)")
            old = []
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
        fetchQueue()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func episodeRefreshCompleted() {
        LogManager.shared.info("🔄 EpisodesViewModel received refresh completion - updating all lists")
        fetchAll()
    }
}
