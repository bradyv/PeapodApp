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
    
    var hGridLayout = [ GridItem(.fixed(350)) ]
    @State private var selectedEpisode: Episode? = nil

    // Add scroll proxy trigger
    @State private var frontEpisodeID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Queue")
                .titleSerif()
                .padding(.leading)

            if queue.isEmpty {
                ZStack {
                    VStack {
                        Text("New episodes are automatically added to the queue.")
                            .textBody()
                    }
                    .frame(maxWidth:.infinity, alignment:.center)
                    
                    ScrollView(.horizontal) {
                        LazyHGrid(rows: hGridLayout, spacing: 16) {
                            EmptyQueueItem()
                            EmptyQueueItem()
                        }
                        .opacity(0.15)
                        .mask(
                            LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.7))
                        )
                    }
                    .disabled(true)
                    .contentMargins(16, for: .scrollContent)
                    .frame(height: 350)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHGrid(rows: hGridLayout, spacing: 16) {
                            ForEach(queue, id: \.id) { episode in
                                QueueItem(episode: episode)
                                    .id(episode.id)
                                    .lineLimit(3)
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
                    .scrollIndicators(.hidden)
                    .contentMargins(16, for: .scrollContent)
                    .onChange(of: queue.first?.id) { newID in
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
