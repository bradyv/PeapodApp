//
//  QueueView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import InfiniteCarousel

struct QueueView: View {
    @FetchRequest(
        sortDescriptors: [
            SortDescriptor(\.nowPlayingItem, order: .reverse),
            SortDescriptor(\.queuePosition)
        ],
        predicate: NSPredicate(format: "isQueued == YES OR nowPlayingItem == YES"),
        animation: .interactiveSpring()
    ) var episodes: FetchedResults<Episode>
    @State private var selectedEpisode: Episode? = nil

    // Add scroll proxy trigger
    @State private var frontEpisodeID: UUID? = nil
    
    var animationNamespace: Namespace.ID

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(episodes, id: \.id) { episode in
                EpisodeItem(episode: episode, displayedInQueue: true)
                    .matchedGeometryEffect(id: episode.id!, in: animationNamespace, isSource: true)
                    .id(episode.id)
                    .lineLimit(3)
                    .padding(.horizontal)
                    .onTapGesture {
                        selectedEpisode = episode
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top,24)
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
    }
}
