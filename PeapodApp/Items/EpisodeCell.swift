//
//  EpisodeCell.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-09-12.
//

import SwiftUI
import Pow

struct EpisodeCell: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @State private var selectedPodcast: Podcast? = nil
    @State private var selectedEpisode: Episode? = nil
    @State private var workItem: DispatchWorkItem?
    @State private var favoriteCount = 0
    @Namespace private var namespace
    
    var showPodcast: Bool? = true
    
    // Computed properties based on unified state
    private var isPlaying: Bool {
        player.isPlayingEpisode(episode)
    }
    
    private var isLoading: Bool {
        player.isLoadingEpisode(episode)
    }
    
    private var playbackPosition: Double {
        player.getProgress(for: episode)
    }
    
    var body: some View {
        let hasStarted = isPlaying || player.hasStartedPlayback(for: episode) || player.getProgress(for: episode) > 0.1
        // Podcast Info Row
        HStack(spacing: 16) {
            ArtworkView(url: episode.episodeImage ?? episode.podcast?.image ?? "", size: 100, cornerRadius: 24, tilt: false)
            
            // Episode Meta
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing:4) {
                        if episode.isPlayed {
                            ZStack {
                                Image(systemName:"checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .textMini()
                            }
                            .background(Color.background)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.background, lineWidth: 1)
                            )
                        }
                        
                        if showPodcast == true {
                            Text(episode.podcast?.title ?? "Podcast title")
                                .lineLimit(1)
                                .textDetailEmphasis()
                        }
                    }
                    
                    Text(getRelativeDateString(from: episode.airDate ?? Date.distantPast))
                        .textDetail()
                }
                
                EpisodeDetails(episode: episode)
            }
            .frame(maxWidth: .infinity, alignment: .leading) 
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button {
                if episode.isQueued {
                    withAnimation {
                        removeFromQueue(episode, episodesViewModel: episodesViewModel)
                    }
                } else {
                    withAnimation {
                        toggleQueued(episode, episodesViewModel: episodesViewModel)
                    }
                }
            } label: {
                Label(episode.isQueued ? "Archive" : "Add to Up Next", systemImage:episode.isQueued ? "archivebox" : "text.append")
            }
            Button {
                withAnimation {
                    toggleFav(episode)
                }
            } label: {
                Label(episode.isFav ? "Undo" : "Add to Favorites", systemImage: episode.isFav ? "heart.slash" : "heart")
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                toggleQueued(episode)
            } label: {
                Label(episode.isQueued ? "Archive" : "Up Next", systemImage: episode.isQueued ? "archivebox" : "text.append")
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .leading) {
            Button {
                toggleFav(episode)
            } label: {
                Label(episode.isFav ? "Undo" : "Favorite", systemImage: episode.isFav ? "heart.slash" : "heart")
            }
            .tint(.red)
        }
    }
}


struct EmptyEpisodeCell: View {
    var body: some View {
        HStack(spacing: 16) {
            // Artwork
            SkeletonItem(width:100, height:100, cornerRadius:24)
            
            // Episode Meta
            VStack(alignment: .leading, spacing: 8) {
                // Podcast Title + Release
                HStack {
                    SkeletonItem(width:100, height:16, cornerRadius:4)
                    
                    SkeletonItem(width:50, height:14, cornerRadius:4)
                }
                
                // Episode Title + Description
                VStack(alignment: .leading, spacing: 2) {
                    SkeletonItem(width:200, height:20, cornerRadius:4)
                    
                    SkeletonItem(height:16, cornerRadius:4)
                    
                    SkeletonItem(height:16, cornerRadius:4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
