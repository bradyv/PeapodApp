//
//  ToggleFav.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI

@MainActor func toggleFav(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    guard let context = episode.managedObjectContext else { return }
    
    if episode.isFav {
        // Remove from favorites playlist
        removeEpisodeFromPlaylist(episode, playlistName: "Favorites")
    } else {
        // Add to favorites playlist
        addEpisodeToPlaylist(episode, playlistName: "Favorites")
    }
    
    do {
        try context.save()
    } catch {
        print("Failed to toggle episode favorite: \(error)")
    }
}
