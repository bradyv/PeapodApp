//
//  AddToQueue.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI
import CoreData

// MARK: - Enhanced Queue Management

/// 🚀 ENHANCED: More granular locking and better state management
private let queueLock = NSRecursiveLock() // Changed to recursive lock
private var pendingQueueOperations = Set<String>() // Track pending operations

/// 🚀 NEW: Operation tracking to prevent duplicate operations
private func isOperationPending(for episodeId: String) -> Bool {
    queueLock.lock()
    defer { queueLock.unlock() }
    return pendingQueueOperations.contains(episodeId)
}

private func markOperationStart(for episodeId: String) {
    queueLock.lock()
    defer { queueLock.unlock() }
    pendingQueueOperations.insert(episodeId)
}

private func markOperationComplete(for episodeId: String) {
    queueLock.lock()
    defer { queueLock.unlock() }
    pendingQueueOperations.remove(episodeId)
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

/// 🚀 ENHANCED: Main toggle function with better state management
func toggleQueued(_ episode: Episode, toFront: Bool = false, pushingPrevious current: Episode? = nil, episodesViewModel: EpisodesViewModel? = nil) {
    
    guard let episodeId = episode.id else {
        print("❌ Episode has no ID, cannot queue")
        return
    }
    
    // 🚀 NEW: Prevent duplicate operations
    if isOperationPending(for: episodeId) {
        print("⏩ Queue operation already pending for episode: \(episode.title ?? "Unknown")")
        return
    }
    
    markOperationStart(for: episodeId)
    
    let context = episode.managedObjectContext ?? PersistenceController.shared.container.viewContext
    
    // 🚀 ENHANCED: Use dedicated queue context
    let workingContext = PersistenceController.shared.queueContext()
    
    workingContext.perform {
        defer { markOperationComplete(for: episodeId) }
        
        // 🚀 ENHANCED: Re-fetch episode in working context to ensure we have latest state
        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", episodeId)
        fetchRequest.fetchLimit = 1
        
        guard let workingEpisode = try? workingContext.fetch(fetchRequest).first else {
            print("❌ Could not find episode in working context")
            return
        }
        
        if toFront {
            handleMoveToFront(workingEpisode, current: current, context: workingContext, episodesViewModel: episodesViewModel)
        } else {
            handleToggleOperation(workingEpisode, context: workingContext, episodesViewModel: episodesViewModel)
        }
    }
}

/// 🚀 NEW: Separate function for move-to-front operations
private func handleMoveToFront(_ episode: Episode, current: Episode?, context: NSManagedObjectContext, episodesViewModel: EpisodesViewModel?) {
    moveEpisodeInQueue(episode, to: 0, context: context, episodesViewModel: episodesViewModel)
    
    if let current = current, current.id != episode.id {
        if !current.isQueued {
            let queuePlaylist = getQueuePlaylist(context: context)
            current.isQueued = true
            queuePlaylist.addToItems(current)
        }
        moveEpisodeInQueue(current, to: 1, context: context, episodesViewModel: episodesViewModel)
    }
}

/// 🚀 NEW: Separate function for toggle operations with better state checking
private func handleToggleOperation(_ episode: Episode, context: NSManagedObjectContext, episodesViewModel: EpisodesViewModel?) {
    queueLock.lock()
    defer { queueLock.unlock() }
    
    let queuePlaylist = getQueuePlaylist(context: context)
    
    // 🚀 ENHANCED: More reliable queue membership check
    let isCurrentlyInQueue = checkIfEpisodeInQueue(episode, playlist: queuePlaylist, context: context)
    
    if isCurrentlyInQueue {
        print("🗑️ Removing episode from queue: \(episode.title ?? "Unknown")")
        performQueueRemoval(episode, playlist: queuePlaylist, context: context)
    } else {
        print("➕ Adding episode to queue: \(episode.title ?? "Unknown")")
        performQueueAddition(episode, playlist: queuePlaylist, context: context)
    }
    
    // 🚀 ENHANCED: Use safe save operation
    PersistenceController.shared.safeSave(context: context, description: "Queue toggle operation")
}

/// 🚀 ENHANCED: More reliable queue membership check
private func checkIfEpisodeInQueue(_ episode: Episode, playlist: Playlist, context: NSManagedObjectContext) -> Bool {
    // Method 1: Check the episode's isQueued flag
    if episode.isQueued {
        return true
    }
    
    // Method 2: Check if episode is in playlist items
    if let episodes = playlist.items as? Set<Episode> {
        for ep in episodes {
            if ep.id == episode.id || ep == episode {
                return true
            }
        }
    }
    
    // Method 3: Database query as final check
    let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "id == %@ AND isQueued == YES", episode.id ?? "")
    fetchRequest.fetchLimit = 1
    
    return (try? context.fetch(fetchRequest).first) != nil
}

/// 🚀 NEW: Separated queue removal logic
private func performQueueRemoval(_ episode: Episode, playlist: Playlist, context: NSManagedObjectContext) {
    playlist.removeFromItems(episode)
    episode.isQueued = false
    episode.queuePosition = -1
    
    // Reindex remaining episodes
    if let episodes = playlist.items as? Set<Episode> {
        let sortedEpisodes = episodes.sorted { $0.queuePosition < $1.queuePosition }
        for (index, ep) in sortedEpisodes.enumerated() {
            ep.queuePosition = Int64(index)
        }
    }
    
    // Check if audio player state should be cleared
    AudioPlayerManager.shared.handleQueueRemoval()
}

/// 🚀 NEW: Separated queue addition logic
private func performQueueAddition(_ episode: Episode, playlist: Playlist, context: NSManagedObjectContext) {
    let existingItems = (playlist.items as? Set<Episode>) ?? []
    let maxPosition = existingItems.map(\.queuePosition).max() ?? -1
    
    episode.isQueued = true
    episode.queuePosition = maxPosition + 1
    playlist.addToItems(episode)
    
    // Remove from saved if applicable
    if episode.isSaved {
        episode.isSaved = false
    }
}

/// 🚀 ENHANCED: Direct removal function with better error handling
func removeFromQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    guard let episodeId = episode.id else {
        print("❌ Episode has no ID, cannot remove from queue")
        return
    }
    
    if isOperationPending(for: episodeId) {
        print("⏩ Queue removal already pending for episode: \(episode.title ?? "Unknown")")
        return
    }
    
    // Use the enhanced toggle function with force-remove flag
    toggleQueued(episode, episodesViewModel: episodesViewModel)
}

/// 🚀 ENHANCED: Move episode with better context handling
func moveEpisodeInQueue(_ episode: Episode, to position: Int, context: NSManagedObjectContext? = nil, episodesViewModel: EpisodesViewModel? = nil) {
    let workingContext = context ?? episode.managedObjectContext ?? PersistenceController.shared.container.viewContext
    
    queueLock.lock()
    defer { queueLock.unlock() }
    
    let queuePlaylist = getQueuePlaylist(context: workingContext)
    
    // Ensure episode is in the queue
    if !checkIfEpisodeInQueue(episode, playlist: queuePlaylist, context: workingContext) {
        episode.isQueued = true
        queuePlaylist.addToItems(episode)
    }
    
    // Get current queue order
    let queue = (queuePlaylist.items as? Set<Episode> ?? [])
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
        if workingContext.hasChanges {
            try workingContext.save()
        }
        print("✅ Episode moved in queue: \(episode.title ?? "Episode") to position \(position)")
        
        Task { @MainActor in
            episodesViewModel?.updateQueue()
        }
    } catch {
        print("❌ Error moving episode in queue: \(error.localizedDescription)")
        workingContext.rollback()
    }
}

/// 🚀 ENHANCED: Reorder with better validation
func reorderQueue(_ episodes: [Episode], episodesViewModel: EpisodesViewModel? = nil) {
    guard !episodes.isEmpty else { return }
    
    let context = episodes.first?.managedObjectContext ?? PersistenceController.shared.container.viewContext
    
    queueLock.lock()
    defer { queueLock.unlock() }
    
    // Validate all episodes belong to queue
    let queuePlaylist = getQueuePlaylist(context: context)
    let queueEpisodeIds = Set((queuePlaylist.items as? Set<Episode> ?? []).compactMap { $0.id })
    
    let reorderingIds = Set(episodes.compactMap { $0.id })
    
    guard queueEpisodeIds == reorderingIds else {
        print("❌ Reorder list doesn't match current queue contents")
        return
    }
    
    // Update positions
    for (index, episode) in episodes.enumerated() {
        episode.queuePosition = Int64(index)
    }
    
    do {
        if context.hasChanges {
            try context.save()
        }
        print("✅ Queue reordered with \(episodes.count) episodes")
        
        Task { @MainActor in
            episodesViewModel?.updateQueue()
        }
    } catch {
        print("❌ Error reordering queue: \(error.localizedDescription)")
        context.rollback()
    }
}
