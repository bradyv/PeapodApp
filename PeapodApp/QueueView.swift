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
        sortDescriptors: [SortDescriptor(\.queuePosition)],
        predicate: NSPredicate(format: "isQueued == YES AND nowPlayingItem == NO"),
        animation: .interactiveSpring()
    )
    var queue: FetchedResults<Episode>
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "isSubscribed == YES"),
        animation: .default
    ) var subscriptions: FetchedResults<Podcast>
    @State private var selectedEpisode: Episode? = nil

    // Add scroll proxy trigger
    @State private var frontEpisodeID: UUID? = nil

    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                if queue.count > 0 {
                    Text("Up Next")
                        .headerSection()
                        .padding(.leading)
                        .padding(.bottom, 4)
                }
                
                VStack(spacing:24) {
                    ForEach(queue, id: \.id) { episode in
                        EpisodeItem(episode:episode, displayedInQueue: true)
                            .id(episode.id)
                            .lineLimit(3)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                }
                .padding(.horizontal)
                
                //            ScrollViewReader { proxy in
                //                ScrollView(.horizontal) {
                //                    LazyHStack(spacing:16) {
                //                        if queue.isEmpty {
                //                            ZStack {
                //                                GeometryReader { geometry in
                //                                    HStack(spacing:16) {
                //                                        ForEach(0..<2, id: \.self) { _ in
                //                                            EmptyQueueItem()
                //                                                .opacity(0.15)
                //                                        }
                //                                    }
                //                                    .frame(width: geometry.size.width, alignment:.leading)
                //                                    .mask(
                //                                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                //                                                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.8))
                //                                    )
                //                                }
                //
                //                                VStack {
                //                                    Text("Nothing to play")
                //                                        .titleCondensed()
                //
                //                                    Text(subscriptions.isEmpty ? "Add some podcasts to get started." : "New episodes are automatically added.")
                //                                        .textBody()
                //                                }
                //                                .offset(x:-16)
                //                                .frame(maxWidth: .infinity)
                //                                .zIndex(1)
                //                            }
                //                            .frame(width: UIScreen.main.bounds.width, height: 250)
                //                        } else {
                //                            ForEach(queue, id: \.id) { episode in
                //                                QueueItem(episode: episode)
                //                                    .id(episode.id)
                //                                    .lineLimit(3)
                //                                    .onTapGesture {
                //                                        selectedEpisode = episode
                //                                    }
                //                                    .scrollTransition { content, phase in
                //                                        content
                //                                            .opacity(phase.isIdentity ? 1 : 0.5) // Apply opacity animation
                //                                            .scaleEffect(y: phase.isIdentity ? 1 : 0.92) // Apply scale animation
                //                                    }
                //                            }
                //                        }
                //                    }
                //                    .scrollTargetLayout()
                //                }
                //                .disabled(queue.isEmpty)
                //                .scrollIndicators(.hidden)
                //                .contentMargins(.horizontal,16, for: .scrollContent)
                //                .sheet(item: $selectedEpisode) { episode in
                //                    EpisodeView(episode: episode)
                //                        .modifier(PPSheet())
                //                }
                //                .onChange(of: queue.first?.id) { oldID, newID in
                //                    if let id = newID {
                //                        DispatchQueue.main.async {
                //                            withAnimation {
                //                                proxy.scrollTo(id, anchor: .leading)
                //                            }
                //                        }
                //                    }
                //                }
                //            }
            }
            .frame(maxWidth: .infinity)
            .padding(.top,24)
            .sheet(item: $selectedEpisode) { episode in
                EpisodeView(episode: episode)
                    .modifier(PPSheet())
            }
    }
}
