//
//  EpisodeActionButtons.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-10-08.
//

import SwiftUI
import Pow

struct ArchiveButton: View {
    @ObservedObject var episode: Episode
    let removeFromQueue: (Episode) -> Void
    let toggleQueued: (Episode) -> Void
    
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
            Label(
                episode.isQueued ? "Archive" : "Add to Up Next",
                systemImage: episode.isQueued ? "rectangle.portrait.on.rectangle.portrait.slash" : "rectangle.portrait.on.rectangle.portrait.angled"
            )
            .contentTransition(.symbolEffect(.replace))
            .textButton()
        }
    }
}

struct MarkAsPlayedButton: View {
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    
    var body: some View {
        Button(action: {
            withAnimation {
                player.markAsPlayed(for: episode, manually: true)
            }
        }) {
            Label(
                episode.isPlayed ? "Mark Unplayed" : "Mark as Played",
                systemImage: episode.isPlayed ? "checkmark.arrow.trianglehead.counterclockwise" : "checkmark.circle"
            )
            .contentTransition(.symbolEffect(.replace))
            .textButton()
        }
    }
}

struct FavoriteButton: View {
    @ObservedObject var episode: Episode
    @Binding var favoriteCount: Int
    let toggleFav: (Episode) -> Void
    
    var body: some View {
        Button(action: {
            withAnimation {
                let wasFavorite = episode.isFav
                toggleFav(episode)
                
                if !wasFavorite && episode.isFav {
                    favoriteCount += 1
                }
            }
        }) {
            Label(episode.isFav ? "Undo Favorite" : "Favorite", systemImage: episode.isFav ? "heart.slash" : "heart")
                .textButton()
        }
        .labelStyle(.iconOnly)
    }
}

struct EpisodeContextMenu: View {
    @ObservedObject var episode: Episode
    @State private var favoriteCount = 0
    
    var body: some View {
        Menu {
            EpisodeContextActions(episode:episode)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }
}

struct EpisodeContextActions: View {
    @ObservedObject var episode: Episode
    @State private var favoriteCount = 0
    
    var body: some View {
        ArchiveButton(
            episode: episode,
            removeFromQueue: { ep in removeFromQueue(ep) },
            toggleQueued: { ep in toggleQueued(ep) }
        )
        
        MarkAsPlayedButton(episode: episode)
        
        FavoriteButton(
            episode: episode,
            favoriteCount: $favoriteCount,
            toggleFav: { ep in toggleFav(ep) }
        )
        
        Divider()
        
        
        Section(episode.podcast?.title ?? "") {
            NavigationLink {
                PodcastDetailView(feedUrl: episode.podcast?.feedUrl ?? "")
            } label: {
                Label("View Podcast", systemImage: "widget.small")
            }
        }
    }
}
