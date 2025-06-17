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
    let context = episode.managedObjectContext ?? PersistenceController.shared.container.viewContext

    // If we're moving to front (usually for playback), use specialized functions
    if toFront {
        // Put this episode at position 0
        moveEpisodeInQueue(episode, to: 0)
        
        // If there's a 'current' episode to push to position 1, do that only if it's not the same as the main episode
        if let current = current, current.id != episode.id {
            // Make sure current is in the queue
            if !current.isQueued {
                // Add to queue first if not already there
                let queuePlaylist = getQueuePlaylist(context: context)
                current.isQueued = true
                queuePlaylist.addToItems(current)
                try? context.save()
            }
            
            // Now move it to position 1
            moveEpisodeInQueue(current, to: 1)
        }
    } else {
        // This is a toggle operation - if in queue, remove; if not in queue, add
        let queuePlaylist = getQueuePlaylist(context: context)
        
        if let episodes = queuePlaylist.items as? Set<Episode>, episodes.contains(episode) {
            // Episode is in queue - remove it
            removeFromQueue(episode)
        } else {
            // Episode is not in queue - add it to the end
            let existingItems = (queuePlaylist.items as? Set<Episode>) ?? []
            let maxPosition = existingItems.map(\.queuePosition).max() ?? -1
            
            // Set episode properties
            episode.isQueued = true
            episode.queuePosition = maxPosition + 1
            
            // Add to playlist
            queuePlaylist.addToItems(episode)
            
            if episode.isSaved {
                episode.isSaved.toggle()
            }
            
            do {
                try context.save()
                print("Added episode to queue: \(episode.title ?? "Episode")")
            } catch {
                print("Error adding episode to queue: \(error.localizedDescription)")
                context.rollback()
            }
        }
    }
    
    // Always update the episodes view model if provided
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
    
    if !toFront {
        // For toggle operations (not moving to front), reindex to ensure proper sequence
        reindexQueuePositions(context: context)
    }
}

/// Directly remove an episode from the queue
func removeFromQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    let context = episode.managedObjectContext ?? PersistenceController.shared.container.viewContext
    
    // Lock to prevent concurrent modifications
    queueLock.lock()
    defer { queueLock.unlock() }
    
    let queuePlaylist = getQueuePlaylist(context: context)
    
    // ENHANCED: More robust checking
    guard let episodes = queuePlaylist.items as? Set<Episode> else {
        print("❌ No episodes found in queue playlist")
        return
    }
    
    // CRITICAL: Check if episode is actually in the queue using multiple criteria
    let episodeInQueue = episodes.first { ep in
        // Check by object identity first
        if ep == episode {
            return true
        }
        // Fallback: check by ID if available
        if let epID = ep.id, let episodeID = episode.id, epID == episodeID {
            return true
        }
        // Fallback: check by title as last resort
        if let epTitle = ep.title, let episodeTitle = episode.title,
           epTitle == episodeTitle && ep.podcast?.title == episode.podcast?.title {
            return true
        }
        return false
    }
    
    guard let foundEpisode = episodeInQueue else {
        print("⚠️ Episode not found in queue: \(episode.title ?? "Unknown")")
        print("📊 Queue contains \(episodes.count) episodes:")
        for (index, ep) in episodes.enumerated() {
            print("   \(index): \(ep.title?.prefix(30) ?? "No title") - isQueued: \(ep.isQueued) - position: \(ep.queuePosition)")
        }
        return
    }
    
    // Remove the found episode
    queuePlaylist.removeFromItems(foundEpisode)
    foundEpisode.isQueued = false
    foundEpisode.queuePosition = -1
    
    print("✅ Removing episode from queue: \(foundEpisode.title ?? "Episode")")
    
    // Reindex remaining episodes
    let remainingEpisodes = (queuePlaylist.items as? Set<Episode> ?? [])
        .sorted { $0.queuePosition < $1.queuePosition }
    
    for (index, ep) in remainingEpisodes.enumerated() {
        ep.queuePosition = Int64(index)
    }
    
    do {
        try context.save()
        print("✅ Episode removed from queue successfully: \(foundEpisode.title ?? "Episode")")
        print("📊 Queue now contains \(remainingEpisodes.count) episodes")
    } catch {
        print("❌ Error removing from queue: \(error.localizedDescription)")
        context.rollback()
        return
    }
    
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
    
    // Check if audio player state should be cleared
    AudioPlayerManager.shared.handleQueueRemoval()
}

/// Move an episode to a specific position in the queue
func moveEpisodeInQueue(_ episode: Episode, to position: Int, episodesViewModel: EpisodesViewModel? = nil) {
    let context = episode.managedObjectContext ?? PersistenceController.shared.container.viewContext
    
    // Lock to prevent concurrent modifications
    queueLock.lock()
    defer { queueLock.unlock() }
    
    let queuePlaylist = getQueuePlaylist(context: context)
    
    // Ensure episode is in the queue
    if let episodes = queuePlaylist.items as? Set<Episode>, !episodes.contains(episode) {
        // Add to queue if not already there
        episode.isQueued = true
        queuePlaylist.addToItems(episode)
    }
    
    // Get current queue order
    let queue = (queuePlaylist.items as? Set<Episode> ?? [])
        .sorted { $0.queuePosition < $1.queuePosition }
    
    // Create a new ordering by removing the episode and inserting at the right position
    var reordered = queue.filter { $0.id != episode.id }
    let targetPosition = min(max(0, position), reordered.count)
    reordered.insert(episode, at: targetPosition)
    
    // Update positions
    for (index, ep) in reordered.enumerated() {
        ep.queuePosition = Int64(index)
    }
    
    do {
        try context.save()
        print("Episode moved in queue: \(episode.title ?? "Episode") to position \(position)")
    } catch {
        print("Error moving episode in queue: \(error.localizedDescription)")
        context.rollback()
    }
    
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
}

/// Reorder the entire queue to match the provided array order
func reorderQueue(_ episodes: [Episode], episodesViewModel: EpisodesViewModel? = nil) {
    guard !episodes.isEmpty else { return }
    
    let context = episodes.first?.managedObjectContext ?? PersistenceController.shared.container.viewContext
    
    // Lock to prevent concurrent modifications
    queueLock.lock()
    defer { queueLock.unlock() }
    
    // Update positions based on array order
    for (index, episode) in episodes.enumerated() {
        episode.queuePosition = Int64(index)
    }
    
    do {
        try context.save()
        print("Queue reordered with \(episodes.count) episodes")
    } catch {
        print("Error reordering queue: \(error.localizedDescription)")
        context.rollback()
    }
    
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
}
