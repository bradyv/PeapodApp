//
//  LatestEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-04.
//

import SwiftUI

struct LatestEpisodes: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.airDate, order: .reverse)],
        predicate: NSPredicate(format: "podcast != nil AND podcast.isSubscribed == YES"),
        animation: .interactiveSpring()
    )
    var latest: FetchedResults<Episode>
    @State private var selectedEpisode: Episode? = nil
    
    
    var body: some View {
        Spacer().frame(height:24)
        Text("Latest Episodes")
            .titleSerif()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading).padding(.top,24)
        
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(Array(latest.enumerated()), id: \.1.id) { index, episode in
                    FadeInView(delay: Double(index) * 0.2) {
                        EpisodeItem(episode: episode)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                }
                .sheet(item: $selectedEpisode) { episode in
                    EpisodeView(episode: episode)
                        .modifier(PPSheet())
                }
            }
        }
        .maskEdge(.bottom)
        .refreshable {
            EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
        }
        .ignoresSafeArea(edges: .all)
    }
}
