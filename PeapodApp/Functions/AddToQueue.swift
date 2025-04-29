//
//  AddToQueue.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI
import CoreData

func toggleQueued(_ episode: Episode, toFront: Bool = false, pushingPrevious current: Episode? = nil, episodesViewModel: EpisodesViewModel? = nil) {
    let context = episode.managedObjectContext ?? PersistenceController.shared.container.viewContext

    // Fetch or create the Queue playlist
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", "Queue")
    let queuePlaylist = (try? context.fetch(request).first) ?? {
        let newPlaylist = Playlist(context: context)
        newPlaylist.name = "Queue"
        return newPlaylist
    }()

    // Remove episode and optional previous if already present
    var queue = (queuePlaylist.items as? Set<Episode> ?? []).filter {
        $0.id != episode.id && $0.id != current?.id
    }

    if toFront {
        episode.isQueued = true
        queuePlaylist.addToItems(episode)

        // Only push previous episode if it's already queued
        if let current = current,
           (queuePlaylist.items as? Set<Episode>)?.contains(current) == true {
            current.isQueued = true
            queuePlaylist.addToItems(current)
        }

        let reordered = [episode] + (current.map { [$0] } ?? []) + queue
        for (index, ep) in reordered.enumerated() {
            ep.queuePosition = Int64(index)
        }
    } else {
        if (queuePlaylist.items as? Set<Episode>)?.contains(episode) == true {
            queuePlaylist.removeFromItems(episode)
            episode.isQueued = false
            episode.queuePosition = -1
        } else {
            queuePlaylist.addToItems(episode)
            episode.isQueued = true

            let existingItems = (queuePlaylist.items as? Set<Episode>)?.filter { $0 != episode } ?? []
            let maxPosition = existingItems.map(\.queuePosition).max() ?? -1
            episode.queuePosition = maxPosition + 1
        }
    }

    try? context.save()
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
}
