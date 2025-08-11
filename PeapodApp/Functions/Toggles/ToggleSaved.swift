//
//  ToggleSaved.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-08-10.
//

//import SwiftUI
//
//@MainActor func togglePlayed(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
//    guard let context = episode.managedObjectContext else { return }
//    
//    if episode.isPlayed {
//        // Remove from played playlist
//        removeEpisodeFromPlaylist(episode, playlistName: "Played")
//        // Also remove from queue if it was there
//        if episode.isQueued {
//            removeFromQueue(episode, episodesViewModel: episodesViewModel)
//        }
//    } else {
//        // Add to played playlist
//        addEpisodeToPlaylist(episode, playlistName: "Played")
//        episode.playbackPosition = 0 // Reset position when manually marked as played
//        
//        // Remove from queue if it was there
//        if episode.isQueued {
//            removeFromQueue(episode, episodesViewModel: episodesViewModel)
//        }
//    }
//    
//    do {
//        try context.save()
//    } catch {
//        print("Failed to toggle episode played status: \(error)")
//    }
//}
