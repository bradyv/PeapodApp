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
    let episode: Episode

    @State private var workItem: DispatchWorkItem?
    @State private var favoriteCount = 0
    @Namespace private var namespace
    
    var body: some View {
        VStack(alignment: .leading) {
            // Podcast Info Row
            PodcastDetailsRow(episode: episode, displayedInQueue: true)
            
            // Episode Meta
            EpisodeDetails(data: data, displayedInQueue: true)
            
            // Episode Actions
            HStack {
                // Isolated play button - only this rebuilds on player changes
                EpisodePlayButton(episode: episode)
                
                Spacer()
                
                // Context menu - no longer depends on player state
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
}

struct EpisodePlayButton: View {
    let episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    
    private var isLoading: Bool {
        player.isLoadingEpisode(episode)
    }
    
    var body: some View {
        Button(action: {
            guard !isLoading else { return }
            player.togglePlayback(for: episode, episodesViewModel: episodesViewModel)
        }) {
            HStack {
                if isLoading {
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
