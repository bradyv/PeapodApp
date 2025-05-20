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
    // Use the shared queue manager for queue episodes
    @Published var queueManager = QueueManager.shared
    
    // Other episode categories
    @Published var latest: [Episode] = []
    @Published var unplayed: [Episode] = []
    @Published var saved: [Episode] = []
    @Published var favs: [Episode] = []
    @Published var old: [Episode] = []

    // Core Data controllers for categories that need real-time updates
    private var savedController: NSFetchedResultsController<Episode>?
    private var favsController: NSFetchedResultsController<Episode>?
    var context: NSManagedObjectContext?

    override init() {
        super.init()
    }

    static func placeholder() -> EpisodesViewModel {
        EpisodesViewModel()
    }

    func setup(context: NSManagedObjectContext) {
        self.context = context
        setupSavedController()
        setupFavsController()
        fetchAll()
    }

    // MARK: - Fetched Results Controllers

    private func setupSavedController() {
        guard let context else { return }

        let request = Episode.savedEpisodesRequest()
        
        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        controller.delegate = self

        do {
            try controller.performFetch()
            self.saved = controller.fetchedObjects ?? []
        } catch {
            print("Failed to fetch saved episodes: \(error)")
        }

        self.savedController = controller
    }
    
    private func setupFavsController() {
        guard let context else { return }

        let request = Episode.favEpisodesRequest()
        
        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        controller.delegate = self

        do {
            try controller.performFetch()
            self.favs = controller.fetchedObjects ?? []
        } catch {
            print("Failed to fetch favorite episodes: \(error)")
        }

        self.favsController = controller
    }

    // MARK: - Fetch Methods

    func fetchLatest() {
        guard let context else { return }
        
        Task.detached(priority: .userInitiated) {
            let request = Episode.latestEpisodesRequest()
            let episodes = (try? context.fetch(request)) ?? []
            
            await MainActor.run {
                self.latest = episodes
            }
        }
    }

    func fetchUnplayed() {
        guard let context else { return }
        
        Task.detached(priority: .userInitiated) {
            let request = Episode.unplayedEpisodesRequest()
            let episodes = (try? context.fetch(request)) ?? []
            
            await MainActor.run {
                self.unplayed = episodes
            }
        }
    }

    func fetchSaved() {
        // Saved episodes are managed by the fetched results controller
        // so this is just for manual refresh if needed
        do {
            try savedController?.performFetch()
            self.saved = savedController?.fetchedObjects ?? []
        } catch {
            print("Failed to refresh saved episodes: \(error)")
        }
    }
    
    func fetchFavs() {
        // Favorite episodes are managed by the fetched results controller
        // so this is just for manual refresh if needed
        do {
            try favsController?.performFetch()
            self.favs = favsController?.fetchedObjects ?? []
        } catch {
            print("Failed to refresh favorite episodes: \(error)")
        }
    }

    func fetchOld() {
        guard let context else { return }
        
        Task.detached(priority: .userInitiated) {
            let request = Episode.oldEpisodesRequest()
            let episodes = (try? context.fetch(request)) ?? []
            
            await MainActor.run {
                self.old = episodes
            }
        }
    }

    func fetchAll() {
        fetchLatest()
        fetchUnplayed()
        fetchSaved()
        fetchFavs()
        fetchOld()
    }

    func refreshEpisodes() {
        guard let context else { return }
        
        // Perform episode refresh in background
        Task.detached(priority: .userInitiated) {
            PodcastManager.shared.refreshAllSubscribedPodcasts()
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension EpisodesViewModel: @preconcurrency NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if controller == savedController {
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.saved = updatedEpisodes
        } else if controller == favsController {
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.favs = updatedEpisodes
        }
    }
}
