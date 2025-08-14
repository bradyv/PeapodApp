//
//  LatestEpisodes.swift
//  PeapodApp
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
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
    }
    
    @ViewBuilder
    private var miniView: some View {
        VStack {
            Spacer().frame(height: 44)
            
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
                
                episodesList
            }
        }
    }
    
    @ViewBuilder
    private var fullView: some View {
        ScrollView {
            if !mini {
                podcastFilter
                Spacer().frame(height: 24)
            }
            
            if filteredEpisodes.isEmpty {
                emptyState
            } else {
                episodesList
            }
        }
        .navigationTitle(showAll ? "Recent Releases" : "Unplayed")
        .background(Color.background)
        .toolbar {
            if !mini {
                ToolbarItem {
                    Button(action: {
                        showAll.toggle()
                    }) {
                        Label("Filter", systemImage: "line.3.horizontal.decrease")
                    }
                    .if(!showAll, transform: { $0.buttonStyle(.glassProminent) })
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .toast()
        .refreshable {
            if !mini {
                EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                    toastManager.show(message: "Peapod is up to date", icon: "sparkles")
                    LogManager.shared.info("✨ Refreshed latest episodes")
                }
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
        LazyVStack(alignment: .leading) {
            ForEach(filteredEpisodes, id: \.id) { episode in
                FadeInView(delay: mini ? 0 : 0.3) {
                    EpisodeItem(episode: episode, showActions: true)
                        .lineLimit(3)
                        .padding(.bottom, 24)
                        .padding(.horizontal)
                        .animation(.easeOut(duration: 0.2), value: showAll)
                        .onTapGesture {
                            selectedEpisode = episode
                        }
                }
            }
        }
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
