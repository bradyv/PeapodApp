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
        let frame = UIScreen.main.bounds.width - 48
        let hasStarted = isPlaying || player.hasStartedPlayback(for: episode) || player.getProgress(for: episode) > 0.1
        // Podcast Info Row
        HStack(spacing: 16) {
            ArtworkView(url: episode.episodeImage ?? episode.podcast?.image ?? "", size: 100, cornerRadius: 16)
                .matchedTransitionSource(id: episode.id, in: namespace)
            
            // Episode Meta
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(episode.podcast?.title ?? "Podcast title")
                        .lineLimit(1)
                        .textDetailEmphasis()
                    
                    Text(getRelativeDateString(from: episode.airDate ?? Date.distantPast))
                        .textDetail()
                }
                
                Text(episode.title ?? "Episode title")
                    .foregroundStyle(Color.heading)
                    .textBody()
                    .lineLimit(1)
                
                // Episode Actions
                HStack {
                    // ▶️ Playback Button
                    Button(action: {
                        guard !isLoading else { return }
                        player.togglePlayback(for: episode)
                    }) {
                        HStack {
                            PPCircularPlayButton(
                                episode: episode,
                                displayedInQueue: false,
                                buttonSize: 20
                            )
                            
                            Text("\(player.getStableRemainingTime(for: episode, pretty: true))")
                                .contentTransition(.numericText())
                        }
                    }
                    .buttonStyle(
                        PPButton(
                            type: .transparent,
                            colorStyle: .monochrome,
                            hierarchical: false
                        )
                    )
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            let wasFavorite = episode.isFav
                            toggleFav(episode, episodesViewModel: episodesViewModel)
                            
                            // Only increment counter when favoriting (not unfavoriting)
                            if !wasFavorite && episode.isFav {
                                favoriteCount += 1
                            }
                        }
                    }) {
                        Label("Favorite", systemImage: episode.isFav ? "heart.fill" : "heart")
                    }
                    .buttonStyle(
                        PPButton(
                            type: .transparent,
                            colorStyle: .monochrome,
                            iconOnly: true
                        )
                    )
                    .changeEffect(
                        .spray(origin: UnitPoint(x: 0.25, y: 0.5)) {
                          Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        }, value: favoriteCount)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading) 
        }
        .contentShape(Rectangle())
        .frame(width: frame, alignment: .leading)
    }
}
