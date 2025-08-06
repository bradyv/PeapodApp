//
//  FavEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI

struct FavEpisodesView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    var namespace: Namespace.ID
    
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
                        EpisodeItem(episode: episode, showActions: true, namespace: namespace)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                    }
                }
            }
        }
        .background(Color.background)
        .toolbar {
            ToolbarItem(placement: .largeTitle) {
                Text("Favorites")
                    .titleSerif()
                    .frame(maxWidth:.infinity, alignment:.leading)
           }
        }
        .onAppear {
            episodesViewModel.fetchFavs()
        }
        .scrollDisabled(episodesViewModel.favs.isEmpty)
    }
}

struct FavEpisodesMini: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @Environment(\.managedObjectContext) private var context
    @State private var selectedEpisode: Episode? = nil
    @State private var selectedPodcast: Podcast? = nil
    var namespace: Namespace.ID
    
    var body: some View {
        VStack {
            if !episodesViewModel.favs.isEmpty {
                Spacer().frame(height:24)
                NavigationLink {
                    FavEpisodesView(namespace: namespace)
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
                        EpisodeItem(episode: episode, showActions: true, namespace: namespace)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                    }
                }
            }
        }
        .onAppear {
            episodesViewModel.fetchFavs()
        }
    }
}
