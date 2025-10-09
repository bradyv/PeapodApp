//
//  EpisodeItem.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Pow

struct EpisodeItem: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
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
        VStack(alignment: .leading) {
            // Podcast Info Row
            PodcastDetailsRow(episode: episode, displayedInQueue: true)
            
            // Episode Meta
            EpisodeDetails(episode: episode, displayedInQueue: true)
            
            // Episode Actions
            HStack {
//                let hasStarted = isPlaying || player.hasStartedPlayback(for: episode) || player.getProgress(for: episode) > 0.1
                PlayButton
                
//                if hasStarted {
//                    MarkAsPlayedButton
//                } else {
//                    ArchiveButton
//                }
                
                Spacer()
                
                Menu {
                    ArchiveButton(episode:episode)
                    MarkAsPlayedButton(episode:episode)
                    FavButton(episode:episode)
                    
                    Section(episode.podcast?.title ?? "") {
                        NavigationLink {
                            PodcastDetailView(feedUrl: episode.podcast?.feedUrl ?? "")
                        } label: {
                            Label("View Podcast", systemImage: "widget.small")
                        }
                    }
                } label: {
                    Label("More", systemImage:"ellipsis")
                        .frame(width:36,height:36)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.white)
                .textButton()
                
//                FavButton
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            // Cancel any previous work item
            workItem?.cancel()
            // Create a new work item
            let item = DispatchWorkItem {
                Task.detached(priority: .background) {
                    await player.writeActualDuration(for: episode)
                }
            }
            workItem = item
            // Schedule after 0.5 seconds (adjust as needed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
        }
        .onDisappear {
            // Cancel if the user scrolls away before debounce interval
            workItem?.cancel()
        }
    }
    
    @ViewBuilder
    var PlayButton: some View {
        // ▶️ Playback Button
        Button(action: {
            guard !isLoading else { return }
            player.togglePlayback(for: episode)
        }) {
            HStack {
                PPCircularPlayButton(
                    episode: episode,
                    displayedInQueue: true,
                    buttonSize: 20
                )
                
                Text("\(player.getStableRemainingTime(for: episode, pretty: true))")
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.white)
                    .textButton()
            }
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }
}
