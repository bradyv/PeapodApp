//
//  FavEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI

struct FavEpisodesView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @State private var selectedEpisode: Episode? = nil
    
    var body: some View {
        ScrollView {
            if episodesViewModel.favs.isEmpty {
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
            } else {
                ForEach(episodesViewModel.favs, id: \.id) { episode in
                    FadeInView(delay: 0.3) {
                        EpisodeItem(episode: episode, showActions: true)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                }
            }
        }
        .background(Color.background)
        .scrollDisabled(episodesViewModel.favs.isEmpty)
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
    }
}

struct FavEpisodesMini: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @Environment(\.managedObjectContext) private var context
    @State private var selectedEpisode: Episode? = nil
    @State private var selectedPodcast: Podcast? = nil
    
    var body: some View {
        VStack {
            if !episodesViewModel.favs.isEmpty {
                Spacer().frame(height:24)
                NavigationLink {
                    FavEpisodesView()
                        .navigationTitle("Favorites")
                } label: {
                    HStack(alignment:.center) {
                        Text("Favorites")
                            .titleSerifMini()
                            .padding(.leading)
                        
                        Image(systemName: "chevron.right")
                            .textDetailEmphasis()
                    }
                    .frame(maxWidth:.infinity, alignment: .leading)
                }
            
                LazyVStack(alignment: .leading) {
                    ForEach(episodesViewModel.favs.prefix(3), id: \.id) { episode in
                        EpisodeItem(episode: episode, showActions: true)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                }
            }
        }
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
    }
}
