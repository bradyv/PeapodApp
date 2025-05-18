//
//  AddToQueue.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI
import CoreData

// MARK: - Queue Management (Updated for background Core Data operations)

/// Global queue lock to prevent race conditions between different parts of the app
private let queueLock = NSLock()

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

/// Add, remove, or toggle an episode in the queue (Updated for background operations)
func toggleQueued(_ episode: Episode, toFront: Bool = false, pushingPrevious current: Episode? = nil, episodesViewModel: EpisodesViewModel? = nil) {
    
    // Get object IDs for background operations
    let episodeObjectID = episode.objectID
    let currentObjectID = current?.objectID
    
    // Update episodes view model immediately on main thread
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
    
    // Do the heavy lifting in background
    Task.detached(priority: .userInitiated) {
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = PersistenceController.shared.container.viewContext
        
        await backgroundContext.perform {
            // Lock to prevent concurrent modifications
            queueLock.lock()
            defer { queueLock.unlock() }
            
            do {
                guard let backgroundEpisode = try backgroundContext.existingObject(with: episodeObjectID) as? Episode else { return }
                
                if toFront {
                    // Move to front of queue
                    moveEpisodeToFrontInBackground(
                        episode: backgroundEpisode,
                        currentObjectID: currentObjectID,
                        context: backgroundContext
                    )
                } else {
                    // Toggle operation
                    toggleEpisodeInQueueInBackground(
                        episode: backgroundEpisode,
                        context: backgroundContext
                    )
                }
                
                try backgroundContext.save()
            } catch {
                print("Error in toggleQueued: \(error.localizedDescription)")
                backgroundContext.rollback()
            }
        }
        
        // Save to persistent store
        await MainActor.run {
            try? PersistenceController.shared.container.viewContext.save()
            episodesViewModel?.updateQueue()
        }
    }
}

/// Remove an episode from the queue (Updated for background operations)
func removeFromQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    let objectID = episode.objectID
    
    // Update UI immediately
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
    
    // Do Core Data operations in background
    Task.detached(priority: .background) {
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = PersistenceController.shared.container.viewContext
        
        await backgroundContext.perform {
            // Lock to prevent concurrent modifications
            queueLock.lock()
            defer { queueLock.unlock() }
            
            do {
                guard let backgroundEpisode = try backgroundContext.existingObject(with: objectID) as? Episode else { return }
                
                let queuePlaylist = getQueuePlaylist(context: backgroundContext)
                
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
                    
                    try backgroundContext.save()
                    print("Episode removed from queue: \(backgroundEpisode.title ?? "Episode")")
                }
            } catch {
                print("Error removing from queue: \(error.localizedDescription)")
                backgroundContext.rollback()
            }
        }
        
        // Save to persistent store
        await MainActor.run {
            try? PersistenceController.shared.container.viewContext.save()
            episodesViewModel?.updateQueue()
        }
    }
}

/// Move an episode to a specific position in the queue (Updated for background operations)
func moveEpisodeInQueue(_ episode: Episode, to position: Int, episodesViewModel: EpisodesViewModel? = nil) {
    let objectID = episode.objectID
    
    // Update UI immediately
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
    
    // Do Core Data operations in background
    Task.detached(priority: .background) {
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = PersistenceController.shared.container.viewContext
        
        await backgroundContext.perform {
            // Lock to prevent concurrent modifications
            queueLock.lock()
            defer { queueLock.unlock() }
            
            do {
                guard let backgroundEpisode = try backgroundContext.existingObject(with: objectID) as? Episode else { return }
                
                let queuePlaylist = getQueuePlaylist(context: backgroundContext)
                
                // Ensure episode is in the queue
                if let episodes = queuePlaylist.items as? Set<Episode>, !episodes.contains(backgroundEpisode) {
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
                
                try backgroundContext.save()
                print("Episode moved in queue: \(backgroundEpisode.title ?? "Episode") to position \(position)")
            } catch {
                print("Error moving episode in queue: \(error.localizedDescription)")
                backgroundContext.rollback()
            }
        }
        
        // Save to persistent store
        await MainActor.run {
            try? PersistenceController.shared.container.viewContext.save()
            episodesViewModel?.updateQueue()
        }
    }
}

/// Reorder the entire queue (Updated for background operations)
func reorderQueue(_ episodes: [Episode], episodesViewModel: EpisodesViewModel? = nil) {
    guard !episodes.isEmpty else { return }
    
    let objectIDs = episodes.map { $0.objectID }
    
    // Update UI immediately
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
    
    // Do Core Data operations in background
    Task.detached(priority: .background) {
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = PersistenceController.shared.container.viewContext
        
        await backgroundContext.perform {
            // Lock to prevent concurrent modifications
            queueLock.lock()
            defer { queueLock.unlock() }
            
            do {
                // Get background episodes in the same order
                var backgroundEpisodes: [Episode] = []
                for objectID in objectIDs {
                    if let episode = try backgroundContext.existingObject(with: objectID) as? Episode {
                        backgroundEpisodes.append(episode)
                    }
                }
                
                // Update positions based on array order
                for (index, episode) in backgroundEpisodes.enumerated() {
                    episode.queuePosition = Int64(index)
                }
                
                try backgroundContext.save()
                print("Queue reordered with \(backgroundEpisodes.count) episodes")
            } catch {
                print("Error reordering queue: \(error.localizedDescription)")
                backgroundContext.rollback()
            }
        }
        
        // Save to persistent store
        await MainActor.run {
            try? PersistenceController.shared.container.viewContext.save()
            episodesViewModel?.updateQueue()
        }
    }
}

// MARK: - Private Background Helper Methods

private func moveEpisodeToFrontInBackground(episode: Episode, currentObjectID: NSManagedObjectID?, context: NSManagedObjectContext) {
    let queuePlaylist = getQueuePlaylist(context: context)
    
    // Put this episode at position 0
    if !episode.isQueued {
        episode.isQueued = true
        queuePlaylist.addToItems(episode)
    }
    
    // Get current queue order
    guard let items = queuePlaylist.items as? Set<Episode> else { return }
    let queue = items.sorted { $0.queuePosition < $1.queuePosition }
    
    // If already at position 0, handle current episode if needed
    if queue.first?.id == episode.id {
        if let currentObjectID = currentObjectID {
            if let current = try? context.existingObject(with: currentObjectID) as? Episode,
               current.id != episode.id {
                // Make sure current is in the queue at position 1
                if !current.isQueued {
                    current.isQueued = true
                    queuePlaylist.addToItems(current)
                }
                // Move to position 1
                moveCurrentEpisodeToPosition1(current: current, queue: queue, context: context)
            }
        }
        return
    }
    
    // Create new ordering with episode at front
    var reordered = queue.filter { $0.id != episode.id }
    reordered.insert(episode, at: 0)
    
    // Handle current episode if provided
    if let currentObjectID = currentObjectID {
        if let current = try? context.existingObject(with: currentObjectID) as? Episode,
           current.id != episode.id {
            // Make sure current is in the queue
            if !current.isQueued {
                current.isQueued = true
                queuePlaylist.addToItems(current)
            }
            
            // Remove current from reordered array and insert at position 1
            reordered = reordered.filter { $0.id != current.id }
            if reordered.count >= 1 {
                reordered.insert(current, at: 1)
            } else {
                reordered.append(current)
            }
        }
    }
    
    // Update positions
    for (index, ep) in reordered.enumerated() {
        ep.queuePosition = Int64(index)
    }
    
    print("Episode moved to front of queue: \(episode.title ?? "Episode")")
}

private func moveCurrentEpisodeToPosition1(current: Episode, queue: [Episode], context: NSManagedObjectContext) {
    var reordered = queue.filter { $0.id != current.id }
    if reordered.count >= 1 {
        reordered.insert(current, at: 1)
    } else {
        reordered.append(current)
    }
    
    // Update positions
    for (index, ep) in reordered.enumerated() {
        ep.queuePosition = Int64(index)
    }
}

private func toggleEpisodeInQueueInBackground(episode: Episode, context: NSManagedObjectContext) {
    let queuePlaylist = getQueuePlaylist(context: context)
    
    if let episodes = queuePlaylist.items as? Set<Episode>, episodes.contains(episode) {
        // Episode is in queue - remove it
        queuePlaylist.removeFromItems(episode)
        episode.isQueued = false
        episode.queuePosition = -1
        
        // Reindex remaining episodes
        let remainingEpisodes = (queuePlaylist.items as? Set<Episode> ?? [])
            .sorted { $0.queuePosition < $1.queuePosition }
        
        for (index, ep) in remainingEpisodes.enumerated() {
            ep.queuePosition = Int64(index)
        }
        
        print("Episode removed from queue: \(episode.title ?? "Episode")")
    } else {
        // Episode is not in queue - add it to the end
        let existingItems = (queuePlaylist.items as? Set<Episode>) ?? []
        let maxPosition = existingItems.map(\.queuePosition).max() ?? -1
        
        // Set episode properties
        episode.isQueued = true
        episode.queuePosition = maxPosition + 1
        
        // Add to playlist
        queuePlaylist.addToItems(episode)
        
        // Remove from saved if it's saved
        if episode.isSaved {
            episode.isSaved = false
            episode.savedDate = nil
        }
        
        print("Added episode to queue: \(episode.title ?? "Episode")")
    }
}

/// Reindex all episodes in the queue (Updated for background operations)
func reindexQueuePositions(context: NSManagedObjectContext) {
    let playlist = getQueuePlaylist(context: context)
    guard let items = playlist.items as? Set<Episode> else { return }
    
    let sortedItems = items.sorted { $0.queuePosition < $1.queuePosition }
    
    // Reassign positions to ensure they're sequential
    for (index, episode) in sortedItems.enumerated() {
        episode.queuePosition = Int64(index)
    }
    
    print("Queue reindexed with \(sortedItems.count) episodes")
}
