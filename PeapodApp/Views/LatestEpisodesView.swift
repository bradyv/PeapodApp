//
//  LatestEpisodes.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-04.
//

import SwiftUI
import Kingfisher

struct EpisodeCarousel: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @Environment(\.managedObjectContext) private var context
    @Namespace private var namespace
    
    var filter: String?
    
    private var episodes: [Episode] {
        if filter == "unplayed" {
            return episodesViewModel.unplayed
        } else if filter == "favs" {
            return episodesViewModel.favs
        } else {
            return episodesViewModel.latest
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if !episodes.isEmpty {
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
                .scrollClipDisabled(true)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }
    
    @ViewBuilder
    private var episodesCells: some View {
        LazyHStack(spacing: 8) {
            ForEach(episodes, id: \.id) { episode in
                NavigationLink {
                    EpisodeView(episode:episode)
                        .navigationTransition(.zoom(sourceID: "\(episode.id ?? "")-latest", in: namespace))
                } label: {
                    EpisodeCell(
                        data: EpisodeCellData(from: episode),
                        episode: episode
                    )
                    .frame(width: UIScreen.main.bounds.width - 40)
                    .matchedTransitionSource(id: "\(episode.id ?? "")-latest", in: namespace)
                }
            }
        }
        .scrollTargetLayout()
    }
}

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
        if mini {
            miniView
        } else {
            fullView
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
                .scrollClipDisabled(true)
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
                .listRowSeparator(.hidden)
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.plain)
        .background(Color.background)
        .toolbar {
            ToolbarItem(placement:.largeSubtitle) {
                HStack(spacing: 2) {
                    Text(selectedPodcast?.id == nil ? "All Podcasts" : "Filtering: **\(selectedPodcast?.title ?? "")**")
                        .textMini()
                        .frame(maxWidth:.infinity, alignment:.leading)
                }
            }
            ToolbarItem(placement:.subtitle) {
                Text(selectedPodcast?.id == nil ? "All Podcasts" : selectedPodcast?.title ?? "")
                    .textMini()
            }
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    Button(action: {
                        selectedPodcast = nil
                    }) {
                        Text("All Podcasts")
                    }
                    
                    Divider()
                    
                    ForEach(uniquePodcasts, id: \.id) { podcast in
                        Button(action: {
                            selectedPodcast = podcast
                        }) {
                            HStack {
                                KFImage(URL(string:podcast.image ?? ""))
                                    .clipShape(Circle())
                                Text(podcast.title ?? "")
                                    .lineLimit(1)
                                if selectedPodcast?.id == podcast.id {
                                    Image(systemName:"checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName:"line.3.horizontal.decrease")
                }
            }
            
            if !episodesViewModel.queue.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    MiniPlayer()
                    Spacer()
                    MiniPlayerButton()
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
        ForEach(filteredEpisodes, id: \.id) { episode in
            NavigationLink {
                EpisodeView(episode:episode)
                    .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
            } label: {
                EpisodeCell(
                    data: EpisodeCellData(from: episode),
                    episode: episode
                )
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    withAnimation {
                        if episode.isQueued {
                            removeFromQueue(episode, episodesViewModel: episodesViewModel)
                        } else {
                            addToQueue(episode, episodesViewModel: episodesViewModel)
                        }
                    }
                } label: {
                    Label(
                        episode.isQueued ? "Archive" : "Up Next",
                        systemImage: episode.isQueued ? "rectangle.portrait.on.rectangle.portrait.slash" : "rectangle.portrait.on.rectangle.portrait.angled"
                    )
                }
                .tint(.accentColor)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    toggleFav(episode)
                } label: {
                    Label(episode.isFav ? "Undo" : "Favorite",
                          systemImage: episode.isFav ? "heart.slash" : "heart")
                }
                .tint(.orange)
            }
        }
    }
    
    @ViewBuilder
    private var episodesCells: some View {
        LazyHStack(spacing: 8) {
            ForEach(filteredEpisodes, id: \.id) { episode in
                NavigationLink {
                    EpisodeView(episode:episode)
                        .navigationTransition(.zoom(sourceID: "\(episode.id ?? "")-latest", in: namespace))
                } label: {
                    EpisodeCell(
                        data: EpisodeCellData(from: episode),
                        episode: episode
                    )
                    .frame(width: UIScreen.main.bounds.width - 40)
                    .matchedTransitionSource(id: "\(episode.id ?? "")-latest", in: namespace)
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
