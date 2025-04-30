//
//  SavedEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct SavedEpisodes: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    var namespace: Namespace.ID
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:24)
            FadeInView(delay: 0.2) {
                Text("Saved Episodes")
                    .titleSerif()
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .padding(.leading).padding(.top,24)
            }
            
            if episodesViewModel.saved.isEmpty {
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
                        Text("No saved episodes")
                            .titleCondensed()
                        
                        Text("Tap \(Image(systemName:"bookmark")) on any episode you'd like to save for later.")
                            .textBody()
                    }
                }
            } else {
                ForEach(episodesViewModel.saved, id: \.id) { episode in
                    FadeInView(delay: 0.3) {
                        NavigationLink {
                            PPPopover(pushView:false) {
                                EpisodeView(episode: episode, namespace: namespace)
                            }
                            .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
                            .interactiveDismissDisabled(false)
                        } label: {
                            EpisodeItem(episode: episode, savedView:true, namespace: namespace)
                                .lineLimit(3)
                                .padding(.bottom, 24)
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .onAppear {
            episodesViewModel.fetchSaved()
        }
        .maskEdge(.top)
        .maskEdge(.bottom)
        .disabled(episodesViewModel.saved.isEmpty)
    }
}
