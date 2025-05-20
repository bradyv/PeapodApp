//
//  QueueHelpers.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-18.
//

import SwiftUI
import CoreData

// MARK: - Queue Management Functions

/// Toggle an episode in the queue
func toggleQueued(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.toggle(episode)
}

/// Add episode to front of queue (used when starting playback)
func addToFrontOfQueue(_ episode: Episode, pushingPrevious current: Episode? = nil, episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.addToFront(episode, pushingBack: current)
}

/// Remove an episode from the queue
func removeFromQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.remove(episode)
}

/// Move an episode to a specific position in the queue
func moveEpisodeInQueue(_ episode: Episode, to position: Int, episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.move(episode, to: position)
}

/// Reorder the entire queue
func reorderQueue(_ episodes: [Episode], episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.reorder(episodes)
}

// MARK: - Episode State Management

/// Toggle the saved state of an episode
func toggleSaved(_ episode: Episode) {
    Task {
        await EpisodeStateManager.shared.toggleSaved(episode)
    }
}
/// Toggle the favorite state of an episode
func toggleFav(_ episode: Episode) {
    Task {
        await EpisodeStateManager.shared.toggleFav(episode)
    }
}

// MARK: - Playlist Helper

/// Get or create the Queue playlist in the given context
func getQueuePlaylist(context: NSManagedObjectContext) -> Playlist {
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", "Queue")
    
    if let existingPlaylist = try? context.fetch(request).first {
        return existingPlaylist
    } else {
        let newPlaylist = Playlist(context: context)
        newPlaylist.name = "Queue"
        try? context.save()
        return newPlaylist
    }
}
