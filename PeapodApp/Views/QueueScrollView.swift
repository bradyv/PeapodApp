//
//  QueueScrollView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-18.
//

import SwiftUI
import CoreData

struct QueueScrollView: View {
    var queue: [Episode]
    var subscriptions: FetchedResults<Podcast>
    @Binding var selectedEpisode: Episode?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    if queue.isEmpty {
                        QueueEmptyState(subscriptions: subscriptions)
                    } else {
                        NowPlayingItem()
                        ForEach(queue, id: \.self) { episode in
                            QueueItem(episode: episode)
                                .id(episode.objectID)
                                .onTapGesture {
                                    selectedEpisode = episode
                                }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }
}

struct QueueEmptyState: View {
    var subscriptions: FetchedResults<Podcast>

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                HStack(spacing: 16) {
                    ForEach(0..<2, id: \.self) { _ in
                        EmptyQueueItem().opacity(0.15)
                    }
                }
                .frame(width: geometry.size.width, alignment: .leading)
                .mask(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.8)
                    )
                )
            }

            VStack {
                Text("Nothing to play").titleCondensed()
                Text(subscriptions.isEmpty ? "Add some podcasts to get started." : "New episodes are automatically added.")
                    .textBody()
            }
            .offset(x: -16)
            .zIndex(1)
        }
        .frame(width: UIScreen.main.bounds.width, height: 250)
    }
}
