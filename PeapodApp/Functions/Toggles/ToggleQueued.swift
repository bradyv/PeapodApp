//
//  AddToQueue.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI
import CoreData

// MARK: - Queue Management

private let queueLock = NSLock()

/// Get or create the Queue playlist
func getQueuePlaylist(context: NSManagedObjectContext) -> Playlist {
    return getPlaylist(named: "Queue", context: context)
}

/// Toggle episode in queue using playlist system
func toggleQueued(_ episode: Episode, toFront: Bool = false, pushingPrevious current: Episode? = nil, episodesViewModel: EpisodesViewModel? = nil) {
    let context = episode.managedObjectContext ?? PersistenceController.shared.container.viewContext

    if toFront {
        // Move to front for playback
        moveEpisodeInQueue(episode, to: 0)
        
        if let current = current, current.id != episode.id {
            // Ensure current episode is queued
            if !current.isQueued {
                addEpisodeToPlaylist(current, playlistName: "Queue")
            }
            moveEpisodeInQueue(current, to: 1)
        }
    } else {
        // Toggle operation
        if episode.isQueued {
            removeFromQueue(episode)
        } else {
            addToQueue(episode)
        }
    }
    
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
    
    if !toFront {
        reindexQueuePositions(context: context)
    }
}

/// Add episode to queue
private func addToQueue(_ episode: Episode) {
    guard let context = episode.managedObjectContext,
          let episodeId = episode.id else { return }
    
    let queuePlaylist = getQueuePlaylist(context: context)
    
    // Check if already in queue
    if episode.isQueued {
        return
    }
    
    // Get the highest position and add 1
    let existingEpisodes = fetchEpisodesInPlaylist(named: "Queue", context: context)
    let maxPosition = existingEpisodes.map(\.queuePosition).max() ?? -1
    
    episode.queuePosition = maxPosition + 1
    queuePlaylist.addEpisodeId(episodeId)
    
    do {
        try context.save()
        print("Added episode to queue: \(episode.title ?? "Episode")")
    } catch {
        print("Error adding episode to queue: \(error.localizedDescription)")
        context.rollback()
    }
}

/// Remove episode from queue using playlist system
func removeFromQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    guard let context = episode.managedObjectContext,
          let episodeId = episode.id else { return }
    
    queueLock.lock()
    defer { queueLock.unlock() }
    
    let queuePlaylist = getQueuePlaylist(context: context)
    
    // Check if episode is in the queue playlist using episodeIds
    if queuePlaylist.containsEpisode(id: episodeId) {
        LogManager.shared.info("✅ Removing episode from queue: \(episode.title?.prefix(30) ?? "Episode")")
        queuePlaylist.removeEpisodeId(episodeId)
        episode.queuePosition = -1
    } else {
        LogManager.shared.warning("⚠️ Episode not found in queue: \(episode.title?.prefix(30) ?? "Episode")")
        return
    }
    
    // Reindex remaining episodes
    let remainingEpisodes = fetchEpisodesInPlaylist(named: "Queue", context: context)
        .sorted { $0.queuePosition < $1.queuePosition }
    
    for (index, ep) in remainingEpisodes.enumerated() {
        ep.queuePosition = Int64(index)
    }
    
    do {
        try context.save()
        LogManager.shared.info("✅ Episode removed from queue successfully")
    } catch {
        LogManager.shared.error("❌ Error removing from queue: \(error)")
        context.rollback()
        return
    }
    
    Task { @MainActor in
        episodesViewModel?.updateQueue()
    }
    
    AudioPlayerManager.shared.handleQueueRemoval()
}

/// Move episode to specific position in queue
func moveEpisodeInQueue(_ episode: Episode, to position: Int, episodesViewModel: EpisodesViewModel? = nil) {
    guard let context = episode.managedObjectContext,
          let episodeId = episode.id else { return }
    
    queueLock.lock()
    defer { queueLock.unlock() }
    
    let queuePlaylist = getQueuePlaylist(context: context)
    
    // Ensure episode is in the queue
    if !episode.isQueued {
        queuePlaylist.addEpisodeId(episodeId)
    }
    
    // Get current queue order
    let queue = fetchEpisodesInPlaylist(named: "Queue", context: context)
        .sorted { $0.queuePosition < $1.queuePosition }
    
    // Create new ordering
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

/// Reindex queue positions
func reindexQueuePositions(context: NSManagedObjectContext) {
    queueLock.lock()
    defer { queueLock.unlock() }
    
    let episodes = fetchEpisodesInPlaylist(named: "Queue", context: context)
        .sorted { $0.queuePosition < $1.queuePosition }
    
    for (index, episode) in episodes.enumerated() {
        episode.queuePosition = Int64(index)
    }
    
    do {
        try context.save()
        print("Queue reindexed with \(episodes.count) episodes")
    } catch {
        print("Error reindexing queue: \(error.localizedDescription)")
        context.rollback()
    }
}
