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
            EpisodeGridItem(episode: episode)
                .frame(width:100,height:100)
            
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
                        
                        Text(episode.podcast?.title ?? "Podcast title")
                            .lineLimit(1)
                            .textDetailEmphasis()
                    }
                    
                    Text(getRelativeDateString(from: episode.airDate ?? Date.distantPast))
                        .textDetail()
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Line\nLine\nLine")
                        .titleCondensed()
                        .lineLimit(3, reservesSpace: true)
                        .frame(maxWidth: .infinity)
                        .hidden()
                        .overlay(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(episode.title ?? "Episode title")
                                    .titleCondensed()
                                    .lineLimit(2)
                                    .layoutPriority(1)
                                    .multilineTextAlignment(.leading)
                                
                                Text(parseHtml(episode.episodeDescription ?? "Episode description", flat: true))
                                    .textBody()
                                    .lineLimit(2)
                                    .layoutPriority(0)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                Label(episode.isFav ? "Remove from Favorites" : "Add to Favorites", systemImage: episode.isFav ? "heart.slash" : "heart")
            }
        }
    }
}
