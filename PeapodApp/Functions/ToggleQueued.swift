//
//  AddToQueue.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI
import CoreData

// MARK: - Queue Management

/// Global queue lock to prevent race conditions between different parts of the app
private let queueLock = NSLock()

/// Background context helper functions (matching AudioPlayerManager)
private func createBackgroundContext() -> NSManagedObjectContext {
    let context = PersistenceController.shared.container.newBackgroundContext()
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    return context
}

private func performBackgroundSave(_ operation: @escaping (NSManagedObjectContext) -> Void, completion: @escaping () -> Void = {}) {
    let context = createBackgroundContext()
    context.perform {
        operation(context)
        do {
            try context.save()
            DispatchQueue.main.async {
                completion()
            }
        } catch {
            print("❌ Background save error in queue operations: \(error)")
            context.rollback()
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}

/// Fetch the Queue playlist, creating it if needed
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

/// Reindex all episodes in the queue to ensure continuous position values
func reindexQueuePositions(context: NSManagedObjectContext) {
    // Lock to prevent concurrent modifications
    queueLock.lock()
    defer { queueLock.unlock() }
    
    let playlist = getQueuePlaylist(context: context)
    guard let items = playlist.items as? Set<Episode> else { return }
    
    let sortedItems = items.sorted { $0.queuePosition < $1.queuePosition }
    
    // Reassign positions to ensure they're sequential
    for (index, episode) in sortedItems.enumerated() {
        episode.queuePosition = Int64(index)
    }
    
    do {
        try context.save()
        print("Queue reindexed with \(sortedItems.count) episodes")
    } catch {
        print("Error reindexing queue: \(error.localizedDescription)")
        context.rollback()
    }
}

/// Add, remove, or toggle an episode in the queue
func toggleQueued(_ episode: Episode, toFront: Bool = false, pushingPrevious current: Episode? = nil, episodesViewModel: EpisodesViewModel? = nil) {
    let episodeObjectID = episode.objectID
    let currentObjectID = current?.objectID
    
    // If we're moving to front (usually for playback), use specialized functions
    if toFront {
        // Put this episode at position 0
        moveEpisodeInQueue(episode, to: 0, episodesViewModel: episodesViewModel)
        
        // If there's a 'current' episode to push to position 1, do that only if it's not the same as the main episode
        if let current = current, current.id != episode.id {
            // Make sure current is in the queue first, then move to position 1
            performBackgroundSave({ context in
                guard let backgroundCurrent = try? context.existingObject(with: current.objectID) as? Episode else { return }
                
                if !backgroundCurrent.isQueued {
                    let queuePlaylist = getQueuePlaylist(context: context)
                    backgroundCurrent.isQueued = true
                    queuePlaylist.addToItems(backgroundCurrent)
                }
            }) {
                // After ensuring it's in queue, move to position 1
                moveEpisodeInQueue(current, to: 1, episodesViewModel: episodesViewModel)
            }
        }
    } else {
        // This is a toggle operation - if in queue, remove; if not in queue, add
        performBackgroundSave({ context in
            guard let backgroundEpisode = try? context.existingObject(with: episodeObjectID) as? Episode else { return }
            
            let queuePlaylist = getQueuePlaylist(context: context)
            
            if let episodes = queuePlaylist.items as? Set<Episode>, episodes.contains(backgroundEpisode) {
                // Episode is in queue - remove it
                queuePlaylist.removeFromItems(backgroundEpisode)
                backgroundEpisode.isQueued = false
                backgroundEpisode.queuePosition = -1
                
                // Reindex remaining episodes
                let remainingEpisodes = (queuePlaylist.items as? Set<Episode> ?? [])
                    .sorted { $0.queuePosition < $1.queuePosition }
                
                for (index, ep) in remainingEpisodes.enumerated() {
                    ep.queuePosition = Int64(index)
                }
                
                print("Episode removed from queue: \(backgroundEpisode.title ?? "Episode")")
            } else {
                // Episode is not in queue - add it to the end
                let existingItems = (queuePlaylist.items as? Set<Episode>) ?? []
                let maxPosition = existingItems.map(\.queuePosition).max() ?? -1
                
                // Set episode properties
                backgroundEpisode.isQueued = true
                backgroundEpisode.queuePosition = maxPosition + 1
                
                // Add to playlist
                queuePlaylist.addToItems(backgroundEpisode)
                
                if backgroundEpisode.isSaved {
                    backgroundEpisode.isSaved.toggle()
                }
                
                print("Added episode to queue: \(backgroundEpisode.title ?? "Episode")")
            }
        }) {
            // Update UI after background operation completes
            Task { @MainActor in
                episodesViewModel?.updateQueue()
            }
        }
    }
}

/// Directly remove an episode from the queue
func removeFromQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    let episodeObjectID = episode.objectID
    
    performBackgroundSave({ context in
        guard let backgroundEpisode = try? context.existingObject(with: episodeObjectID) as? Episode else { return }
        
        // Lock to prevent concurrent modifications
        queueLock.lock()
        defer { queueLock.unlock() }
        
        let queuePlaylist = getQueuePlaylist(context: context)
        
        // Only proceed if episode is actually in the queue
        if let episodes = queuePlaylist.items as? Set<Episode>, episodes.contains(backgroundEpisode) {
            queuePlaylist.removeFromItems(backgroundEpisode)
            backgroundEpisode.isQueued = false
            backgroundEpisode.queuePosition = -1
            
            // Reindex remaining episodes
            let remainingEpisodes = (queuePlaylist.items as? Set<Episode> ?? [])
                .sorted { $0.queuePosition < $1.queuePosition }
            
            for (index, ep) in remainingEpisodes.enumerated() {
                ep.queuePosition = Int64(index)
            }
            
            print("Episode removed from queue: \(backgroundEpisode.title ?? "Episode")")
        }
    }) {
        // Update UI after background operation completes
        Task { @MainActor in
            episodesViewModel?.updateQueue()
        }
    }
}

/// Move an episode to a specific position in the queue
func moveEpisodeInQueue(_ episode: Episode, to position: Int, episodesViewModel: EpisodesViewModel? = nil) {
    let episodeObjectID = episode.objectID
    
    performBackgroundSave({ context in
        guard let backgroundEpisode = try? context.existingObject(with: episodeObjectID) as? Episode else { return }
        
        // Lock to prevent concurrent modifications
        queueLock.lock()
        defer { queueLock.unlock() }
        
        let queuePlaylist = getQueuePlaylist(context: context)
        
        // Ensure episode is in the queue
        if let episodes = queuePlaylist.items as? Set<Episode>, !episodes.contains(backgroundEpisode) {
            // Add to queue if not already there
            backgroundEpisode.isQueued = true
            queuePlaylist.addToItems(backgroundEpisode)
        }
        
        // Get current queue order
        let queue = (queuePlaylist.items as? Set<Episode> ?? [])
            .sorted { $0.queuePosition < $1.queuePosition }
        
        // Create a new ordering by removing the episode and inserting at the right position
        var reordered = queue.filter { $0.id != backgroundEpisode.id }
        let targetPosition = min(max(0, position), reordered.count)
        reordered.insert(backgroundEpisode, at: targetPosition)
        
        // Update positions
        for (index, ep) in reordered.enumerated() {
            ep.queuePosition = Int64(index)
        }
        
        print("Episode moved in queue: \(backgroundEpisode.title ?? "Episode") to position \(position)")
    }) {
        // Update UI after background operation completes
        Task { @MainActor in
            episodesViewModel?.updateQueue()
        }
    }
}

/// Reorder the entire queue to match the provided array order
func reorderQueue(_ episodes: [Episode], episodesViewModel: EpisodesViewModel? = nil) {
    guard !episodes.isEmpty else { return }
    
    let episodeObjectIDs = episodes.map { $0.objectID }
    
    performBackgroundSave({ context in
        // Lock to prevent concurrent modifications
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Get background versions of episodes and update positions
        let backgroundEpisodes = episodeObjectIDs.compactMap { objectID in
            try? context.existingObject(with: objectID) as? Episode
        }
        
        // Update positions based on array order
        for (index, episode) in backgroundEpisodes.enumerated() {
            episode.queuePosition = Int64(index)
        }
        
        print("Queue reordered with \(backgroundEpisodes.count) episodes")
    }) {
        // Update UI after background operation completes
        Task { @MainActor in
            episodesViewModel?.updateQueue()
        }
    }
}
