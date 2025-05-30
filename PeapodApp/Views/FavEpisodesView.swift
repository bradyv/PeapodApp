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
            Spacer().frame(height:24)
            FadeInView(delay: 0.2) {
                Text("Favorites")
                    .titleSerif()
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .padding(.leading).padding(.top,24)
            }
            
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
                        EpisodeItem(episode: episode, namespace: namespace)
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
        .maskEdge(.top)
        .maskEdge(.bottom)
        .scrollDisabled(episodesViewModel.favs.isEmpty)
    }
}

