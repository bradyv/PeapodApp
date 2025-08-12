//
//  ToggleQueued.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI
import CoreData

// MARK: - Queue Management Functions

private let queueLock = NSLock()

/// Toggle episode in queue using boolean approach
func toggleQueued(_ episode: Episode, toFront: Bool = false, pushingPrevious current: Episode? = nil, episodesViewModel: EpisodesViewModel? = nil) {
    guard let context = episode.managedObjectContext else { return }

    // 🔥 ADD THIS: Notify SwiftUI BEFORE the change
    episode.objectWillChange.send()
    
    // Also notify current episode if it exists
    current?.objectWillChange.send()

    if toFront {
        // Move to front for playback
        moveEpisodeInQueue(episode, to: 0)
        
        if let current = current, current.id != episode.id {
            // Ensure current episode is queued
            if !current.isQueued {
                current.isQueued = true
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
    
    do {
        try context.save()
    } catch {
        LogManager.shared.error("❌ Error saving queue toggle: \(error)")
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
    guard let context = episode.managedObjectContext else { return }
    
    // Check if already in queue
    if episode.isQueued {
        return
    }
    
    episode.isQueued = true
    LogManager.shared.info("✅ Added episode to queue: \(episode.title?.prefix(30) ?? "Episode")")
}

/// Remove episode from queue
func removeFromQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    guard let context = episode.managedObjectContext else { return }
    
    queueLock.lock()
    defer { queueLock.unlock() }
    
    if !episode.isQueued {
        LogManager.shared.warning("⚠️ Episode not in queue: \(episode.title?.prefix(30) ?? "Episode")")
        return
    }
    
    // 🔥 ADD THIS: Notify SwiftUI BEFORE the change
    episode.objectWillChange.send()
    
    LogManager.shared.info("✅ Removing episode from queue: \(episode.title?.prefix(30) ?? "Episode")")
    episode.isQueued = false
    
    // Reindex remaining episodes
    let remainingEpisodes = getQueuedEpisodes(context: context)
        .sorted { $0.queuePosition < $1.queuePosition }
    
    for (index, ep) in remainingEpisodes.enumerated() {
        // 🔥 ADD THIS: Notify each episode that changes
        ep.objectWillChange.send()
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
    guard let context = episode.managedObjectContext else { return }
    
    queueLock.lock()
    defer { queueLock.unlock() }
    
    // 🔥 ADD THIS: Notify SwiftUI BEFORE the change
    episode.objectWillChange.send()
    
    // Ensure episode is in the queue
    if !episode.isQueued {
        episode.isQueued = true
    }
    
    // Get current queue order
    let queue = getQueuedEpisodes(context: context)
        .sorted { $0.queuePosition < $1.queuePosition }
    
    // Create new ordering
    var reordered = queue.filter { $0.id != episode.id }
    let targetPosition = min(max(0, position), reordered.count)
    reordered.insert(episode, at: targetPosition)
    
    // Update positions
    for (index, ep) in reordered.enumerated() {
        // 🔥 ADD THIS: Notify each episode that changes position
        ep.objectWillChange.send()
        ep.queuePosition = Int64(index)
    }
    
    do {
        try context.save()
        LogManager.shared.info("✅ Episode moved in queue: \(episode.title ?? "Episode") to position \(position)")
    } catch {
        LogManager.shared.error("❌ Error moving episode in queue: \(error)")
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
    
    let episodes = getQueuedEpisodes(context: context)
        .sorted { $0.queuePosition < $1.queuePosition }
    
    for (index, episode) in episodes.enumerated() {
        // 🔥 ADD THIS: Notify each episode of position change
        episode.objectWillChange.send()
        episode.queuePosition = Int64(index)
    }
    
    do {
        try context.save()
        LogManager.shared.info("✅ Queue reindexed with \(episodes.count) episodes")
    } catch {
        LogManager.shared.error("❌ Error reindexing queue: \(error)")
        context.rollback()
    }
}

/// Get next queue position
func getNextQueuePosition(context: NSManagedObjectContext) -> Int64 {
    let request: NSFetchRequest<Playback> = Playback.fetchRequest()
    request.predicate = NSPredicate(format: "isQueued == YES")
    request.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.queuePosition, ascending: false)]
    request.fetchLimit = 1
    
    if let maxPlayback = try? context.fetch(request).first {
        return maxPlayback.queuePosition + 1
    }
    return 0
}

// MARK: - Fetch Functions (Updated to use Playback booleans)

/// Get queued episodes
func getQueuedEpisodes(context: NSManagedObjectContext) -> [Episode] {
    let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
    playbackRequest.predicate = NSPredicate(format: "isQueued == YES")
    playbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.queuePosition, ascending: true)]
    
    guard let playbackStates = try? context.fetch(playbackRequest) else { return [] }
    let episodeIds = playbackStates.compactMap { $0.episodeId }
    
    guard !episodeIds.isEmpty else { return [] }
    
    let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
    episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
    
    do {
        let episodes = try context.fetch(episodeRequest)
        // Sort by queue position from the playback states
        return episodes.sorted { $0.queuePosition < $1.queuePosition }
    } catch {
        LogManager.shared.error("❌ Error fetching queued episodes: \(error)")
        return []
    }
}

/// Get played episodes
func getPlayedEpisodes(context: NSManagedObjectContext) -> [Episode] {
    let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
    playbackRequest.predicate = NSPredicate(format: "isPlayed == YES")
    playbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.playedDate, ascending: false)]
    
    guard let playbackStates = try? context.fetch(playbackRequest) else { return [] }
    let episodeIds = playbackStates.compactMap { $0.episodeId }
    
    guard !episodeIds.isEmpty else { return [] }
    
    let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
    episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
    
    do {
        let episodes = try context.fetch(episodeRequest)
        // Sort by played date (newest first)
        return episodes.sorted { ($0.playedDate ?? Date.distantPast) > ($1.playedDate ?? Date.distantPast) }
    } catch {
        LogManager.shared.error("❌ Error fetching played episodes: \(error)")
        return []
    }
}

/// Get favorite episodes
func getFavoriteEpisodes(context: NSManagedObjectContext) -> [Episode] {
    let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
    playbackRequest.predicate = NSPredicate(format: "isFav == YES")
    playbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.favDate, ascending: false)]
    
    guard let playbackStates = try? context.fetch(playbackRequest) else { return [] }
    let episodeIds = playbackStates.compactMap { $0.episodeId }
    
    guard !episodeIds.isEmpty else { return [] }
    
    let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
    episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
    
    do {
        let episodes = try context.fetch(episodeRequest)
        // Sort by favorited date (newest first)
        return episodes.sorted { ($0.favDate ?? Date.distantPast) > ($1.favDate ?? Date.distantPast) }
    } catch {
        LogManager.shared.error("❌ Error fetching favorite episodes: \(error)")
        return []
    }
}

// MARK: - Backward Compatibility Functions

/// Backward compatibility for fetchEpisodesInPlaylist
func fetchEpisodesInPlaylist(named playlistName: String, context: NSManagedObjectContext) -> [Episode] {
    switch playlistName {
    case "Queue":
        return getQueuedEpisodes(context: context)
    case "Played":
        return getPlayedEpisodes(context: context)
    case "Favorites":
        return getFavoriteEpisodes(context: context)
    default:
        LogManager.shared.error("❌ Unknown playlist name: \(playlistName)")
        return []
    }
}
