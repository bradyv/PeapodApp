//
//  QueueView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI

struct QueueView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.id)],
        predicate: NSPredicate(format: "isQueued == YES"),
        animation: .interactiveSpring()
    )
    var queue: FetchedResults<Episode>
    var hGridLayout = [ GridItem(.fixed(350)) ]
    @State private var selectedEpisode: Episode? = nil
    
    var body: some View {
        VStack {
            Text("Queue")
                .titleSerif()
                .padding(.leading)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        
        if queue.isEmpty {
            Text("No episodes in queue")
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ScrollView(.horizontal) {
                    LazyHGrid(rows: hGridLayout, spacing: 16) {
                        ForEach(queue, id: \.id) { episode in
                            QueueItem(episode:episode)
                                .lineLimit(3)
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
                .scrollIndicators(.hidden)
                .contentMargins(16, for: .scrollContent)
            }
            .frame(maxWidth:.infinity)
        }
    }
}
