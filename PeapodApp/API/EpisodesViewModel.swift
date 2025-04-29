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
    @Published var old: [Episode] = []

    private var queueController: NSFetchedResultsController<Episode>?
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

extension EpisodesViewModel: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let updatedEpisodes = controller.fetchedObjects as? [Episode] else { return }
        self.queue = updatedEpisodes
    }
}
