//
//  EpisodeActions.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-09-27.
//

import SwiftUI
import Pow

struct ArchiveButton: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var episode: Episode
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    
    // Add optional color parameters
    var foregroundColor: Color?
    var tintColor: Color?
    
    var body: some View {
        Button(action: {
            if episode.isQueued {
                withAnimation {
                    removeFromQueue(episode)
                }
            } else {
                withAnimation {
                    toggleQueued(episode)
                }
            }
        }) {
            Label(episode.isQueued ? "Archive" : "Up Next", systemImage: episode.isQueued ? "archivebox" : "text.append")
                .contentTransition(.symbolEffect(.replace))
                .foregroundColor(foregroundColor ?? .heading) // Use custom color or default
                .textButton()
        }
        .tint(tintColor) // Apply custom tint if provided
        .buttonStyle(.bordered)
    }
}

struct MarkAsPlayedButton: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    
    // Add optional color parameters
    var foregroundColor: Color?
    var tintColor: Color?
    
    var body: some View {
        Button(action: {
            withAnimation {
                if episode.isQueued {
                    removeFromQueue(episode, episodesViewModel: episodesViewModel)
                }
                player.markAsPlayed(for: episode, manually: true)
            }
        }) {
            Label(episode.isPlayed ? "Mark as Unplayed" : "Mark as Played", systemImage: episode.isPlayed ? "circle.dashed" : "checkmark.circle")
                .contentTransition(.symbolEffect(.replace))
                .foregroundColor(foregroundColor ?? .heading) // Use custom color or default
                .textButton()
        }
        .tint(tintColor) // Apply custom tint if provided
        .buttonStyle(.bordered)
    }
}

struct FavButton: View {
    @ObservedObject var episode: Episode
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @State private var favoriteCount = 0
    
    // Add optional color parameters
    var foregroundColor: Color?
    var tintColor: Color?
    
    var body: some View {
        Button(action: {
            withAnimation {
                let wasFavorite = episode.isFav
                toggleFav(episode, episodesViewModel: episodesViewModel)
                
                if !wasFavorite && episode.isFav {
                    favoriteCount += 1
                }
            }
        }) {
            Label("Favorite", systemImage: episode.isFav ? "heart.fill" : "heart")
                .foregroundColor(foregroundColor ?? .heading) // Use custom color or default
                .textButton()
        }
        .tint(tintColor) // Apply custom tint if provided
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .changeEffect(
            .spray(origin: UnitPoint(x: 0.25, y: 0.5)) {
              Image(systemName: "heart.fill")
                .foregroundStyle(.red)
            }, value: favoriteCount)
    }
}
