//
//  ToggleFav.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI

@MainActor func toggleFav(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    guard let context = episode.managedObjectContext else { return }
    
    // 🔥 ADD THIS: Notify SwiftUI BEFORE the change
    episode.objectWillChange.send()
    
    // Simple boolean toggle
    episode.isFav.toggle()
    
    do {
        try context.save()
        LogManager.shared.info("✅ Toggled favorite for: \(episode.title?.prefix(30) ?? "Episode") -> \(episode.isFav)")
        
        // 🔥 ADD THIS: Force view model refresh
        episodesViewModel?.fetchFavs()
        
    } catch {
        LogManager.shared.error("❌ Failed to toggle episode favorite: \(error)")
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
