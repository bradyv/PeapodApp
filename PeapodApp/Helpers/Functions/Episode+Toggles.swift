//
//  ToggleFav.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI
import CoreData

private let queueLock = NSLock()

/// Toggle episode in queue using boolean approach
@MainActor func toggleQueued(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    guard let context = episode.managedObjectContext else { return }

    if episode.isQueued {
        episode.isQueued = false
        episode.objectWillChange.send()
    } else {
        episode.isQueued = true
        episode.objectWillChange.send()
    }
    
    episodesViewModel?.fetchQueue()
    
    do {
        try context.save()
        LogManager.shared.info("✅ Toggled queue for: \(episode.title?.prefix(30) ?? "Episode") -> \(episode.isQueued)")
        
    } catch {
        LogManager.shared.error("⚠️ Error saving queue toggle: \(error)")
        // Revert the change if save failed
        episode.isQueued.toggle()
        // Also revert the view model
        episodesViewModel?.fetchQueue()
    }
}

/// Add episode to queue
private func addToQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    
    // Check if already in queue
    if episode.isQueued {
        return
    }
    
    episode.isQueued = true
    LogManager.shared.info("✅ Added episode to queue: \(episode.title?.prefix(30) ?? "Episode")")
}

/// Remove episode from queue
@MainActor func removeFromQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    guard let context = episode.managedObjectContext else { return }
    
    if !episode.isQueued {
        LogManager.shared.warning("⚠️ Episode not marked as queued in Core Data, but forcing removal from UI: \(episode.title?.prefix(30) ?? "Episode")")
    }
    
    // 🔥 Immediate change for UI feedback
    episode.isQueued = false
    episode.objectWillChange.send()
    
    // 🔥 CRITICAL: Update EpisodesViewModel immediately for animations
    episodesViewModel?.fetchQueue()
    
    LogManager.shared.info("✅ Removing episode from queue: \(episode.title?.prefix(30) ?? "Episode")")
    
    // 🆕 Check if playback entity can be deleted BEFORE saving
    var shouldDeletePlayback = false
    if let playback = episode.playbackState {
        let canDelete = !playback.isPlayed &&
                       !playback.isFav &&
                       playback.playbackPosition <= 0
        
        if canDelete {
            shouldDeletePlayback = true
            LogManager.shared.info("🗑️ Will delete orphaned playback entity for episode: \(episode.title?.prefix(30) ?? "Episode")")
        }
    }
    
    do {
        try context.save()
        LogManager.shared.info("✅ Episode removed from queue successfully")
        
        // Delete playback entity AFTER successful save if needed
        if shouldDeletePlayback, let playback = episode.playbackState {
            context.delete(playback)
            try context.save()
            LogManager.shared.info("✅ Deleted orphaned playback entity")
        }
    } catch {
        LogManager.shared.error("⚠️ Error removing from queue: \(error)")
        // Revert the change if save failed
        episode.isQueued = true
        context.rollback()
        // Also revert the view model
        episodesViewModel?.fetchQueue()
        return
    }
    
    AudioPlayerManager.shared.handleQueueRemoval()
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
    
    // PERFORMANCE: Only fetch required properties
    playbackRequest.propertiesToFetch = ["episodeId"]
    playbackRequest.returnsObjectsAsFaults = false
    
    guard let playbackStates = try? context.fetch(playbackRequest) else { return [] }
    let episodeIds = playbackStates.compactMap { $0.episodeId }
    
    guard !episodeIds.isEmpty else { return [] }
    
    // PERFORMANCE: Optimized episode fetch
    let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
    episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
    
    // Add performance optimizations
    episodeRequest.fetchBatchSize = 20
    episodeRequest.returnsObjectsAsFaults = false
    episodeRequest.includesPropertyValues = true
    episodeRequest.includesSubentities = false
    episodeRequest.relationshipKeyPathsForPrefetching = ["podcast"]
    
    do {
        let episodes = try context.fetch(episodeRequest)
        // Sort by queue position
        return episodes.sorted { $0.queuePosition < $1.queuePosition }
    } catch {
        LogManager.shared.error("Error fetching queued episodes: \(error)")
        return []
    }
}

/// Get played episodes
func getPlayedEpisodes(context: NSManagedObjectContext) -> [Episode] {
    let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
    playbackRequest.predicate = NSPredicate(format: "isPlayed == YES")
    playbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.playedDate, ascending: false)]
    
    // PERFORMANCE: Only fetch required properties
    playbackRequest.propertiesToFetch = ["episodeId"]
    playbackRequest.returnsObjectsAsFaults = false
    playbackRequest.fetchLimit = 100 // Limit played episodes
    
    guard let playbackStates = try? context.fetch(playbackRequest) else { return [] }
    let episodeIds = playbackStates.compactMap { $0.episodeId }
    
    guard !episodeIds.isEmpty else { return [] }
    
    // PERFORMANCE: Optimized episode fetch
    let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
    episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
    
    // Add performance optimizations
    episodeRequest.fetchBatchSize = 20
    episodeRequest.returnsObjectsAsFaults = false
    episodeRequest.includesPropertyValues = true
    episodeRequest.includesSubentities = false
    episodeRequest.relationshipKeyPathsForPrefetching = ["podcast"]
    
    do {
        let episodes = try context.fetch(episodeRequest)
        // Sort by played date (newest first)
        return episodes.sorted { ($0.playedDate ?? Date.distantPast) > ($1.playedDate ?? Date.distantPast) }
    } catch {
        LogManager.shared.error("Error fetching played episodes: \(error)")
        return []
    }
}

/// Get favorite episodes
func getFavoriteEpisodes(context: NSManagedObjectContext) -> [Episode] {
    // PERFORMANCE: Get episode IDs only in first fetch
    let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
    playbackRequest.predicate = NSPredicate(format: "isFav == YES")
    playbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.favDate, ascending: false)]
    
    // CRITICAL: Only fetch the episodeId property to minimize data transfer
    playbackRequest.propertiesToFetch = ["episodeId"]
    playbackRequest.returnsObjectsAsFaults = false
    
    guard let playbackStates = try? context.fetch(playbackRequest) else { return [] }
    let episodeIds = playbackStates.compactMap { $0.episodeId }
    
    guard !episodeIds.isEmpty else { return [] }
    
    // PERFORMANCE: Optimized episode fetch with all the same optimizations as subscriptions
    let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
    episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
    
    // CRITICAL: Add all the same performance optimizations as subscriptionsFetchRequest
    episodeRequest.fetchBatchSize = 20
    episodeRequest.returnsObjectsAsFaults = false
    episodeRequest.includesPropertyValues = true
    episodeRequest.includesSubentities = false
    episodeRequest.relationshipKeyPathsForPrefetching = ["podcast"] // Prefetch podcast for FavEpisodesView
    episodeRequest.fetchLimit = 100 // Reasonable limit for favorites
    
    do {
        let episodes = try context.fetch(episodeRequest)
        // Sort by favorited date (newest first) using the episode's favDate property
        return episodes.sorted { ($0.favDate ?? Date.distantPast) > ($1.favDate ?? Date.distantPast) }
    } catch {
        LogManager.shared.error("Error fetching favorite episodes: \(error)")
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

@MainActor func toggleFav(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    guard let context = episode.managedObjectContext else { return }
    
    // 🔥 Immediately toggle for instant UI feedback
    episode.isFav.toggle()
    
    // Force SwiftUI to update immediately
    episode.objectWillChange.send()
    
    do {
        try context.save()
        LogManager.shared.info("✅ Toggled favorite for: \(episode.title?.prefix(30) ?? "Episode") -> \(episode.isFav)")
        
        // 🔥 Update view model in background to keep lists in sync
        Task {
            episodesViewModel?.fetchFavs()
        }
        
    } catch {
        LogManager.shared.error("⚠️ Failed to toggle episode favorite: \(error)")
        // Revert the change if save failed
        episode.isFav.toggle()
    }
}

// MARK: - Playlist-style functions for backward compatibility

func addEpisodeToPlaylist(_ episode: Episode, playlistName: String) {
    guard let context = episode.managedObjectContext else { return }
    
    // 🔥 ADD THIS: Notify SwiftUI BEFORE the change
    episode.objectWillChange.send()
    
    switch playlistName {
    case "Queue":
        episode.isQueued = true
    case "Played":
        episode.isPlayed = true
    case "Favorites":
        episode.isFav = true
    default:
        LogManager.shared.error("❌ Unknown playlist name: \(playlistName)")
        return
    }
    
    do {
        try context.save()
        LogManager.shared.info("✅ Added episode to \(playlistName): \(episode.title?.prefix(30) ?? "Episode")")
    } catch {
        LogManager.shared.error("❌ Failed to add episode to \(playlistName): \(error)")
    }
}

func removeEpisodeFromPlaylist(_ episode: Episode, playlistName: String) {
    guard let context = episode.managedObjectContext else { return }
    
    // 🔥 ADD THIS: Notify SwiftUI BEFORE the change
    episode.objectWillChange.send()
    
    switch playlistName {
    case "Queue":
        episode.isQueued = false
    case "Played":
        episode.isPlayed = false
    case "Favorites":
        episode.isFav = false
    default:
        LogManager.shared.error("❌ Unknown playlist name: \(playlistName)")
        return
    }
    
    do {
        try context.save()
        LogManager.shared.info("✅ Removed episode from \(playlistName): \(episode.title?.prefix(30) ?? "Episode")")
    } catch {
        LogManager.shared.error("❌ Failed to remove episode from \(playlistName): \(error)")
    }
}
