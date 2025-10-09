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
            EpisodeContextActions(episode:episode)
        }
        .swipeActions(edge: .trailing) {
            ArchiveButton(
                episode: episode,
                removeFromQueue: { ep in removeFromQueue(ep) },
                toggleQueued: { ep in toggleQueued(ep) }
            )
            .tint(.accentColor)
        }
        .swipeActions(edge: .leading) {
            FavoriteButton(
                episode: episode,
                favoriteCount: $favoriteCount,
                toggleFav: { ep in toggleFav(ep) }
            )
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
