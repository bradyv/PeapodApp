//
//  AddToQueue.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI

func toggleQueued(_ episode: Episode, toFront: Bool = false) {
    let player = AudioPlayerManager.shared
    let context = episode.managedObjectContext
    var queue = fetchQueuedEpisodes().filter { $0.id != episode.id }

    if episode.isQueued {
        // Remove from queue
        episode.isQueued = false
        episode.queuePosition = -1

        if episode.nowPlayingItem {
            episode.nowPlayingItem = false
            player.currentEpisode = nil
            player.persistCurrentEpisodeID(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let next = fetchQueuedEpisodes().sorted(by: { $0.queuePosition < $1.queuePosition }).first {
                    next.nowPlayingItem = true
                    player.currentEpisode = next
                    player.persistCurrentEpisodeID(next.id)
                    try? next.managedObjectContext?.save()
                }
            }
        }

    } else {
        // Add to queue
        let wasEmpty = queue.isEmpty
        episode.isQueued = true
        queue.append(episode)

        for (index, ep) in queue.enumerated() {
            ep.queuePosition = Int64(index)
        }

        if wasEmpty && AudioPlayerManager.shared.currentEpisode == nil {
            episode.nowPlayingItem = true
            player.currentEpisode = episode
            player.persistCurrentEpisodeID(episode.id)
        }
    }

    try? context?.save()
}
