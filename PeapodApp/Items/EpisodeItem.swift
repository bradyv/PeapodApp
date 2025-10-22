//
//  EpisodeItem.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Pow

struct EpisodeItem: View {
    let data: EpisodeCellData
    let episode: Episode  // Keep for actions only
    
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @State private var workItem: DispatchWorkItem?
    @State private var favoriteCount = 0
    @Namespace private var namespace
    
    // Only compute player state when needed
    private var playerState: (isPlaying: Bool, isLoading: Bool, progress: Double) {
        (
            player.isPlayingEpisode(episode),
            player.isLoadingEpisode(episode),
            player.getProgress(for: episode)
        )
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Podcast Info Row
            PodcastDetailsRow(episode: episode, displayedInQueue: true)
            
            // Episode Meta
            EpisodeDetails(data: data, displayedInQueue: true)
            
            // Episode Actions
            HStack {
                PlayButton
                
                Spacer()
                
                Menu {
                    contextMenuContent
                } label: {
                    Label("More", systemImage:"ellipsis")
                        .frame(width:34,height:34)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.white)
                .textButton()
                .glassEffect(.clear.interactive())
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
//        .onAppear {
//            // Cancel any previous work item
//            workItem?.cancel()
//            // Create a new work item
//            let item = DispatchWorkItem {
//                // FIX: Use the shared singleton instead of the environment object
//                Task.detached(priority: .background) {
//                    await AudioPlayerManager.shared.writeActualDuration(for: episode)
//                }
//            }
//            workItem = item
//            // Schedule after 0.5 seconds (adjust as needed)
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: item)
//        }
//        .onDisappear {
//            // Cancel if the user scrolls away before debounce interval
//            workItem?.cancel()
//        }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        ArchiveButton(episode: episode)
        MarkAsPlayedButton(episode: episode)
        FavButton(episode: episode)
        DownloadActionButton(episode: episode)
        
        Section(data.podcastTitle) {
            NavigationLink {
                PodcastDetailView(feedUrl: data.feedUrl)
            } label: {
                Label("View Podcast", systemImage: "widget.small")
            }
        }
    }
    
    @ViewBuilder
    var PlayButton: some View {
        // ▶️ Playback Button
        Button(action: {
            guard !playerState.isLoading else { return }
            player.togglePlayback(for: episode, episodesViewModel: episodesViewModel)
        }) {
            HStack {
                if playerState.isLoading {
                    PPSpinner(color: Color.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    PPCircularPlayButton(
                        episode: episode,
                        displayedInQueue: true,
                        buttonSize: 20
                    )
                }
                
                Text("\(player.getStableRemainingTime(for: episode, pretty: true))")
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.white)
                    .textButton()
            }
        }
        .buttonStyle(.glassProminent)
    }
}
