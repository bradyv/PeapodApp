//
//  FavEpisodes.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI

struct FavEpisodesView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @State private var selectedEpisodeForNavigation: Episode? = nil
    @Namespace private var namespace
    
    let mini: Bool
    let maxItems: Int?
    
    init(mini: Bool = false, maxItems: Int? = nil) {
        self.mini = mini
        self.maxItems = maxItems
    }
    
    private var displayedEpisodes: [Episode] {
        if let maxItems = maxItems {
            return Array(episodesViewModel.favs.prefix(maxItems))
        }
        return episodesViewModel.favs
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
        if !episodesViewModel.favs.isEmpty {
            VStack(spacing: 8) {
                NavigationLink {
                    FavEpisodesView(mini: false)
                        .navigationTitle("Favorites")
                } label: {
                    HStack(alignment: .center) {
                        Text("Favorites")
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
            .scrollClipDisabled(true)
        }
    }
    
    @ViewBuilder
    private var fullView: some View {
        List {
            if episodesViewModel.favs.isEmpty {
                emptyState
            } else {
                episodesList
                    .listRowBackground(Color.clear)
            }
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.plain)
        .background(Color.background)
        .scrollDisabled(episodesViewModel.favs.isEmpty)
        .toolbar {
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
    private var episodesList: some View {
        ForEach(displayedEpisodes, id: \.id) { episode in
            NavigationLink {
                EpisodeView(episode:episode)
                    .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
            } label: {
                EpisodeItem(episode: episode, showActions: false)
                    .lineLimit(3)
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
            ForEach(displayedEpisodes, id: \.id) { episode in
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
        ZStack {
            VStack {
                ForEach(0..<2, id: \.self) { _ in
                    EmptyEpisodeItem()
                        .opacity(0.03)
                }
            }
            .mask(
                LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                               startPoint: .top, endPoint: .init(x: 0.5, y: 0.8))
            )
            
            VStack {
                Text("No favorites")
                    .titleCondensed()
                
                Text("Tap \(Image(systemName:"heart")) on any episode you'd like to favorite.")
                    .textBody()
            }
        }
    }
}
