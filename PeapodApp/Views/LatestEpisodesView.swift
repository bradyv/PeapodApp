//
//  LatestEpisodes.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-04.
//

import SwiftUI

struct LatestEpisodesView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var toastManager: ToastManager
    @State private var selectedEpisode: Episode? = nil
    @State private var showAll = true
    @State private var selectedPodcast: Podcast? = nil
    @State private var selectedEpisodeForNavigation: Episode? = nil
    @Namespace private var namespace
    
    let mini: Bool
    let maxItems: Int?
    
    init(mini: Bool = false, maxItems: Int? = nil) {
        self.mini = mini
        self.maxItems = maxItems
    }
    
    // Computed property to get unique podcasts
    private var uniquePodcasts: [Podcast] {
        let episodes = showAll ? episodesViewModel.latest : episodesViewModel.unplayed
        let podcastsSet = Set(episodes.compactMap { $0.podcast })
        return Array(podcastsSet).sorted(by: { $0.title ?? "" < $1.title ?? "" })
    }
    
    // Computed property to get filtered episodes
    private var filteredEpisodes: [Episode] {
        let episodes = showAll ? episodesViewModel.latest : episodesViewModel.unplayed
        
        let baseEpisodes: [Episode]
        if let selectedPodcast = selectedPodcast {
            baseEpisodes = episodes.filter { $0.podcast?.id == selectedPodcast.id }
        } else {
            baseEpisodes = episodes
        }
        
        if let maxItems = maxItems {
            return Array(baseEpisodes.prefix(maxItems))
        }
        return baseEpisodes
    }
    
    var body: some View {
        Group {
            if mini {
                miniView
            } else {
                fullView
            }
        }
    }
    
    @ViewBuilder
    private var miniView: some View {
        VStack(spacing: 8) {
            if !episodesViewModel.latest.isEmpty {
                NavigationLink {
                    LatestEpisodesView(mini: false)
                        .navigationTitle("Recent Releases")
                } label: {
                    HStack(alignment: .center) {
                        Text("Recent Releases")
                            .titleSerifMini()
                            .padding(.leading)
                        
                        Image(systemName: "chevron.right")
                            .textDetailEmphasis()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                ScrollView(.horizontal) {
                    episodesCells
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }
    
    @ViewBuilder
    private var fullView: some View {
        List {
            episodesList
                .listRowBackground(Color.clear)
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .listStyle(.plain)
        .background(Color.background)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                NowPlayingBar(selectedEpisodeForNavigation: $selectedEpisodeForNavigation)
            }
        }
    }
    
    @ViewBuilder
    private var podcastFilter: some View {
        FadeInView(delay: 0.2) {
            ZStack {
                VStack {
                    Spacer()
                    Divider()
                        .frame(height: 1)
                        .background(Color.surface)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        VStack {
                            Button {
                                withAnimation {
                                    selectedPodcast = nil
                                }
                            } label: {
                                VStack {
                                    Text("All Podcasts")
                                        .foregroundStyle(Color.heading)
                                        .textBody()
                                }
                            }
                            
                            Spacer()
                            
                            Divider()
                                .frame(height: 1)
                                .background(Color.heading)
                                .opacity(selectedPodcast == nil ? 1 : 0)
                        }
                        .opacity(selectedPodcast == nil ? 1 : 0.5)
                        
                        // Show unique podcasts
                        ForEach(uniquePodcasts, id: \.id) { podcast in
                            VStack {
                                Button {
                                    withAnimation {
                                        if selectedPodcast?.id == podcast.id {
                                            selectedPodcast = nil
                                        } else {
                                            selectedPodcast = podcast
                                        }
                                    }
                                } label: {
                                    VStack {
                                        ArtworkView(url: podcast.image ?? "", size: 24, cornerRadius: 4)
                                    }
                                }
                                
                                Divider()
                                    .frame(height: 1)
                                    .background(Color.heading)
                                    .opacity(selectedPodcast?.id == podcast.id ? 1 : 0)
                            }
                            .opacity(selectedPodcast?.id == podcast.id ? 1 : 0.5)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var episodesList: some View {
        ForEach(filteredEpisodes, id: \.id) { episode in
            NavigationLink {
                EpisodeView(episode:episode)
                    .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
            } label: {
                EpisodeItem(episode: episode, showActions: false)
                    .lineLimit(3)
                    .animation(.easeOut(duration: 0.2), value: showAll)
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
    }
    
    @ViewBuilder
    private var episodesCells: some View {
        LazyHStack(spacing: 16) {
            ForEach(filteredEpisodes, id: \.id) { episode in
                NavigationLink {
                    EpisodeView(episode:episode)
                        .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
                } label: {
                    EpisodeCell(episode: episode)
                }
            }
        }
        .scrollTargetLayout()
    }
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 50)
            Image(systemName: "rectangle.stack.badge.xmark")
                .font(.title)
                .foregroundColor(.gray)
            Text("No episodes found")
                .foregroundColor(.gray)
            
            Button {
                selectedPodcast = nil
            } label: {
                Text("Show all episodes")
                    .foregroundColor(.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
