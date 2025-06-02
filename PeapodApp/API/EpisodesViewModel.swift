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
        setupSavedController()
        setupFavsController()
        fetchAll()
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
            print("Failed to fetch queue episodes: \(error)")
        }

        self.queueController = controller
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
            print("Failed to fetch fav episodes: \(error)")
        }

        self.favsController = controller
    }

    func fetchLatest() {
        guard let context else { return }
        let request = Episode.latestEpisodesRequest()
        latest = (try? context.fetch(request)) ?? []
    }

    func fetchUnplayed() {
        guard let context else { return }
        let request = Episode.unplayedEpisodesRequest()
        unplayed = (try? context.fetch(request)) ?? []
    }

    func fetchSaved() {
        guard let context else { return }
        let request = Episode.savedEpisodesRequest()
        saved = (try? context.fetch(request)) ?? []
    }
    
    func fetchFavs() {
        guard let context else { return }
        let request = Episode.favEpisodesRequest()
        favs = (try? context.fetch(request)) ?? []
    }

    func fetchOld() {
        guard let context else { return }
        let request = Episode.oldEpisodesRequest()
        old = (try? context.fetch(request)) ?? []
    }

    func fetchAll() {
        fetchLatest()
        fetchUnplayed()
        fetchSaved()
        fetchOld()
    }

    func refreshEpisodes() {
        guard let context else { return }
        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
            self.fetchAll()
        }
    }

    func updateQueue() {
        do {
            try queueController?.performFetch()
            self.queue = queueController?.fetchedObjects ?? []
        } catch {
            print("Failed to update queue: \(error)")
        }
    }
}

extension EpisodesViewModel: @preconcurrency NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if controller == queueController {
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.queue = updatedEpisodes
        } else if controller == savedController {
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.saved = updatedEpisodes
        } else if controller == favsController { // Add this block
            guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
            self.favs = updatedEpisodes
        }
    }
}
