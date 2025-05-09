//
//  QueueView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct QueueView: View {
    @Binding var currentEpisodeID: String?
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest())
    var subscriptions: FetchedResults<Podcast>
    @State private var selectedEpisode: Episode? = nil
    @ObservedObject var player = AudioPlayerManager.shared
    var namespace: Namespace.ID

    var body: some View {
        Text("Up Next")
            .titleSerif()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading)
            .padding(.bottom, 4)
            .padding(.top, 24)

        if episodesViewModel.queue.isEmpty {
            ZStack(alignment:.top) {
                EmptyQueueItem()
                    .opacity(0.15)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                            startPoint: .top,
                            endPoint: .init(x: 0.5, y: 0.8)
                        )
                    )

                VStack {
                    Image("Peapod.mono")
                        .resizable()
                        .frame(width: 32, height: 23)
                        .opacity(0.35)

                    Text("Nothing to play")
                        .titleCondensed()

                    Text(subscriptions.isEmpty ? "Add some podcasts to get started." : "New episodes are automatically added.")
                        .textBody()
                }
                .offset(x: -16)
                .frame(maxWidth: .infinity)
                .zIndex(1)
            }
            .frame(width: UIScreen.main.bounds.width, height: 250)
        } else {
            TabView {
                ForEach(Array(episodesViewModel.queue.enumerated()), id: \.element.id) { index, episode in
                    QueueItemView(episode: episode, index: index, namespace: namespace) {
                        selectedEpisode = episode
                    }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .frame(height: 500)
        }
    }
}

struct QueueItemView: View {
    @EnvironmentObject var episodeSelectionManager: EpisodeSelectionManager
    let episode: Episode
    let index: Int
    var namespace: Namespace.ID
    var onSelect: () -> Void

    var body: some View {
        VStack {
            QueueItem(episode: episode, namespace: namespace)
                .matchedTransitionSource(id: episode.id, in: namespace)
                .id(episode.id)
                .lineLimit(3)
                .onTapGesture {
                    episodeSelectionManager.selectEpisode(episode)
                }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
