//
//  QueueView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI

struct QueueView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.queuePosition)],
        predicate: NSPredicate(format: "isQueued == YES"),
        animation: .interactiveSpring()
    )
    var queue: FetchedResults<Episode>
    @State private var selectedEpisode: Episode? = nil

    // Add scroll proxy trigger
    @State private var frontEpisodeID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Queue")
                .titleSerif()
                .padding(.leading)
                .padding(.bottom, 4)

            if queue.isEmpty {
                ZStack {
                    Text("New episodes are automatically added to the queue.")
                        .textBody()
                    
                    ScrollView(.horizontal) {
                        LazyHStack {
                            EmptyQueueItem()
                            EmptyQueueItem()
                        }
                        .opacity(0.15)
                        .mask(
                            LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.8))
                        )
                    }
                    .disabled(true)
                    .contentMargins(.horizontal,16, for: .scrollContent)
                    .frame(height: 250)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(queue, id: \.id) { episode in
                                QueueItem(episode: episode)
                                    .id(episode.id)
                                    .lineLimit(3)
                                    .onTapGesture {
                                        selectedEpisode = episode
                                    }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal,16, for: .scrollContent)
                    .sheet(item: $selectedEpisode) { episode in
                        EpisodeView(episode: episode)
                            .modifier(PPSheet())
                    }
                    .onChange(of: queue.first?.id) { oldID, newID in
                        if let id = newID {
                            DispatchQueue.main.async {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
