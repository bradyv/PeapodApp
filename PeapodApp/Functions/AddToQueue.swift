//
//  AddToQueue.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI

func toggleQueued(_ episode: Episode, toFront: Bool = false, pushingPrevious current: Episode? = nil) {
    var queue = fetchQueuedEpisodes().filter { $0.id != episode.id && $0.id != current?.id }

    if toFront {
        episode.isQueued = true
        var reordered = [episode]

        if let current = current {
            current.isQueued = true
            reordered.append(current)
        }

        reordered.append(contentsOf: queue)

        for (index, ep) in reordered.enumerated() {
            ep.queuePosition = Int64(index)
        }
    } else {
        if episode.isQueued {
            episode.isQueued = false
            episode.queuePosition = -1
        } else {
            episode.isQueued = true
            queue.append(episode)

            for (index, ep) in queue.enumerated() {
                ep.queuePosition = Int64(index)
            }
        }
    }

    try? episode.managedObjectContext?.save()
}
