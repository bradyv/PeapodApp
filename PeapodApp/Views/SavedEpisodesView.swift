//
//  SavedEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct SavedEpisodesView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    var namespace: Namespace.ID
    
    var body: some View {
        ScrollView {
            if !episodesViewModel.saved.isEmpty {
                Spacer().frame(height:24)
                FadeInView(delay: 0.2) {
                    Text("Play Later")
                        .titleSerif()
                        .frame(maxWidth:.infinity, alignment: .leading)
                        .padding(.leading).padding(.top,24)
                }
                
                ForEach(episodesViewModel.saved, id: \.id) { episode in
                    FadeInView(delay: 0.3) {
                        EpisodeItem(episode: episode, showActions: true, namespace: namespace)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                    }
                }
            }
        }
        .maskEdge(.top)
        .maskEdge(.bottom)
        .scrollDisabled(episodesViewModel.saved.isEmpty)
    }
}

struct SavedEpisodesMini: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    var namespace: Namespace.ID
    
    var body: some View {
        VStack {
            if !episodesViewModel.saved.isEmpty {
                Spacer().frame(height:24)
                FadeInView(delay: 0.2) {
                    NavigationLink {
                        PPPopover(showBg: true) {
                            SavedEpisodesView(namespace: namespace)
                        }
                    } label: {
                        HStack(alignment:.bottom) {
                            Text("Play Later")
                                .titleSerifSm()
                                .padding(.leading).padding(.top,24)
                            
                            Image(systemName: "chevron.right")
                                .titleCondensed()
                        }
                        .frame(maxWidth:.infinity, alignment: .leading)
                    }
                }
                
                ForEach(episodesViewModel.saved.prefix(3), id: \.id) { episode in
                    FadeInView(delay: 0.3) {
                        EpisodeItem(episode: episode, showActions: true, namespace: namespace)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }
}
