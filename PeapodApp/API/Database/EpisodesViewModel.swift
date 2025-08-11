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
    @Published var saved: [Episode] = [] // This will be removed since you're removing isSaved
    @Published var favs: [Episode] = []
    @Published var old: [Episode] = []

    // Remove NSFetchedResultsController for playlist-based data since we can't use relationships
    var context: NSManagedObjectContext?

    override init() {
        super.init()
    }

    static func placeholder() -> EpisodesViewModel {
        EpisodesViewModel()
    }

    func setup(context: NSManagedObjectContext) {
        self.context = context
        
        // Load all episode lists manually since we can't use NSFetchedResultsController
        // with our playlist-based system
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
    }
    
    @objc private func contextDidSave() {
        // Refresh all lists when Core Data changes
        fetchQueue()
        fetchLatest()
        fetchUnplayed()
        fetchFavs()
        fetchOld()
    }

    // MARK: - Fetch Functions

    func fetchQueue() {
        guard let context = context else { return }
        queue = fetchEpisodesInPlaylist(named: "Queue", context: context)
    }
    
    func fetchLatest() {
        guard let context = context else { return }
        
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        // FIXED: Use EXISTS query to check if there's a subscribed podcast with matching podcastId
        request.predicate = NSPredicate(format: "EXISTS (SELECT p FROM Podcast p WHERE p.id == podcastId AND p.isSubscribed == YES)")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchLimit = 100 // Reasonable limit
        
        do {
            latest = try context.fetch(request)
        } catch {
            LogManager.shared.error("Failed to fetch latest episodes: \(error)")
            latest = []
        }
    }
    
    func fetchUnplayed() {
        guard let context = context else { return }
        
        // Get played episode IDs
        let playedPlaylist = getPlaylist(named: "Played", context: context)
        let playedIds = playedPlaylist.episodeIdArray
        
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        // FIXED: Use EXISTS query for subscribed podcasts
        let subscribedPredicate = NSPredicate(format: "EXISTS (SELECT p FROM Podcast p WHERE p.id == podcastId AND p.isSubscribed == YES)")
        
        if playedIds.isEmpty {
            // No played episodes, so all subscribed episodes with no progress are unplayed
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                subscribedPredicate,
                NSPredicate(format: "playbackPosition == 0")
            ])
        } else {
            // Exclude played episodes
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                subscribedPredicate,
                NSPredicate(format: "NOT (id IN %@)", playedIds),
                NSPredicate(format: "playbackPosition == 0")
            ])
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchLimit = 100
        
        do {
            unplayed = try context.fetch(request)
        } catch {
            LogManager.shared.error("Failed to fetch unplayed episodes: \(error)")
            unplayed = []
        }
    }
    
    func fetchFavs() {
        guard let context = context else { return }
        favs = fetchEpisodesInPlaylist(named: "Favorites", context: context)
    }

    func fetchOld() {
        guard let context = context else { return }
        
        // Get all episode IDs that are in ANY playlist
        let queueIds = getPlaylist(named: "Queue", context: context).episodeIdArray
        let playedIds = getPlaylist(named: "Played", context: context).episodeIdArray
        let favIds = getPlaylist(named: "Favorites", context: context).episodeIdArray
        
        let allPlaylistIds = Set(queueIds + playedIds + favIds)
        
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        // FIXED: Use EXISTS query for unsubscribed podcasts
        let unsubscribedPredicate = NSPredicate(format: "EXISTS (SELECT p FROM Podcast p WHERE p.id == podcastId AND p.isSubscribed == NO)")
        
        if allPlaylistIds.isEmpty {
            request.predicate = unsubscribedPredicate
        } else {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                unsubscribedPredicate,
                NSPredicate(format: "NOT (id IN %@)", Array(allPlaylistIds))
            ])
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.id, ascending: true)]
        request.fetchLimit = 100
        
        do {
            old = try context.fetch(request)
        } catch {
            LogManager.shared.error("Failed to fetch old episodes: \(error)")
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
}
