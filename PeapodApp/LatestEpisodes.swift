//
//  LatestEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-04.
//

import SwiftUI

struct LatestEpisodes: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.airDate, order: .reverse)],
        predicate: NSPredicate(format: "podcast != nil AND podcast.isSubscribed == YES"),
        animation: .interactiveSpring()
    )
    var latest: FetchedResults<Episode>
    @State private var selectedEpisode: Episode? = nil
    
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:24)
            Text("Latest Episodes")
                .titleSerif()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVStack(alignment: .leading) {
                ForEach(latest, id: \.id) { episode in
                    EpisodeItem(episode: episode)
                        .lineLimit(3)
                        .padding(.bottom, 24)
                        .onTapGesture {
                            selectedEpisode = episode
                        }
                }
                .sheet(item: $selectedEpisode) { episode in
                    EpisodeView(episode: episode)
                        .modifier(PPSheet())
                }
            }
        }
        .padding()
        .ignoresSafeArea(edges: .all)
    }
}
