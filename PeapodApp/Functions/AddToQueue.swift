//
//  AddToQueue.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI

func toggleQueued(_ episode: Episode) {
    if episode.isQueued {
        // Remove from queue
        episode.isQueued = false
        episode.queuePosition = -1
    } else {
        // Add to back of the queue
        let queue = fetchQueuedEpisodes()
        let maxPosition = queue.map { $0.queuePosition }.max() ?? -1
        episode.isQueued = true
        episode.queuePosition = maxPosition + 1
    }

    try? episode.managedObjectContext?.save()
}
