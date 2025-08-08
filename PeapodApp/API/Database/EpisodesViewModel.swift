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
    @Published var saved: [Episode] = []
    @Published var favs: [Episode] = []
    @Published var old: [Episode] = []

    private var queueController: NSFetchedResultsController<Episode>?
    private var latestController: NSFetchedResultsController<Episode>?  // NEW
    private var unplayedController: NSFetchedResultsController<Episode>?  // NEW
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
        setupQueueController()
        setupLatestController()  // NEW
        setupUnplayedController()  // NEW
        setupSavedController()
        setupFavsController()
        fetchOld() // Only old episodes still need manual fetching
    }

    private func setupQueueController() {
        guard let context else { return }

        let request = Episode.queueFetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.queuePosition, ascending: true)]

        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        controller.delegate = self

        do {
            try controller.performFetch()
            self.queue = controller.fetchedObjects ?? []
        } catch {
            LogManager.shared.error("Failed to fetch queue episodes: \(error)")
        }

        self.queueController = controller
    }
    
    // NEW: Auto-updating latest episodes
    private func setupLatestController() {
        guard let context else { return }

        let request = Episode.latestEpisodesRequest()
        
        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        controller.delegate = self

        do {
            try controller.performFetch()
            self.latest = controller.fetchedObjects ?? []
        } catch {
            LogManager.shared.error("Failed to fetch latest episodes: \(error)")
        }

        self.latestController = controller
    }
    
    // NEW: Auto-updating unplayed episodes
    private func setupUnplayedController() {
        guard let context else { return }

        let request = Episode.unplayedEpisodesRequest()
        
        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        controller.delegate = self

        do {
            try controller.performFetch()
            self.unplayed = controller.fetchedObjects ?? []
        } catch {
            LogManager.shared.error("Failed to fetch unplayed episodes: \(error)")
        }

        self.unplayedController = controller
    }
    
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
            LogManager.shared.error("Failed to fetch saved episodes: \(error)")
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
            LogManager.shared.error("Failed to fetch fav episodes: \(error)")
        }

        self.favsController = controller
    }

    // These can now be removed since they're auto-updating
    // func fetchLatest() { ... }
    // func fetchUnplayed() { ... }
    // func fetchSaved() { ... }
    // func fetchFavs() { ... }

    func fetchOld() {
        guard let context else { return }
        let request = Episode.oldEpisodesRequest()
        old = (try? context.fetch(request)) ?? []
    }

    func fetchAll() {
        // Only old episodes need manual fetching now
        fetchOld()
        // All others auto-update via NSFetchedResultsController
    }

    func refreshEpisodes() {
        guard let context else { return }
        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
            // Only fetch old episodes since others auto-update
            self.fetchOld()
        }
    }

    func updateQueue() {
        do {
            try queueController?.performFetch()
            self.queue = queueController?.fetchedObjects ?? []
        } catch {
            LogManager.shared.error("Failed to update queue: \(error)")
        }
    }
}

extension EpisodesViewModel: @preconcurrency NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if controller == queueController {
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.queue = updatedEpisodes
        } else if controller == latestController {  // NEW
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.latest = updatedEpisodes
            LogManager.shared.info("📱 Latest episodes auto-updated: \(updatedEpisodes.count) episodes")
        } else if controller == unplayedController {  // NEW
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.unplayed = updatedEpisodes
            LogManager.shared.info("📱 Unplayed episodes auto-updated: \(updatedEpisodes.count) episodes")
        } else if controller == savedController {
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.saved = updatedEpisodes
        } else if controller == favsController {
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.favs = updatedEpisodes
        }
    }
}
