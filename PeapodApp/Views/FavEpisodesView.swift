//
//  FavEpisodes.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI

struct FavEpisodesView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @State private var selectedEpisode: Episode? = nil
    
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
            if !episodesViewModel.favs.isEmpty {
                Spacer().frame(height: 24)
                
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
                
                episodesList
            }
        }
    }
    
    @ViewBuilder
    private var fullView: some View {
        ScrollView {
            if episodesViewModel.favs.isEmpty {
                emptyState
            } else {
                episodesList
            }
        }
        .background(Color.background)
        .scrollDisabled(episodesViewModel.favs.isEmpty)
    }
    
    @ViewBuilder
    private var episodesList: some View {
        LazyVStack(alignment: .leading) {
            ForEach(displayedEpisodes, id: \.id) { episode in
                EpisodeItem(episode: episode, showActions: false)
                    .lineLimit(3)
                    .padding(.bottom, 24)
                    .padding(.horizontal)
                    .onTapGesture {
                        selectedEpisode = episode
                    }
                    .contextMenu {
                        Button {
                            withAnimation {
                                if episode.isQueued {
                                    removeFromQueue(episode, episodesViewModel: episodesViewModel)
                                } else {
                                    toggleQueued(episode, episodesViewModel: episodesViewModel)
                                }
                            }
                        } label: {
                            Label(episode.isQueued ? "Archive" : "Add to Up Next", systemImage: episode.isQueued ? "archivebox" : "text.append")
                        }
                        Button {
                            withAnimation {
                                toggleFav(episode, episodesViewModel: episodesViewModel)
                            }
                        } label: {
                            Label(episode.isFav ? "Remove from Favorites" : "Add to Favorites", systemImage: episode.isFav ? "heart.slash" : "heart")
                        }
                    }
            }
        }
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
