//
//  PodcastDetailView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import FeedKit
import Kingfisher

struct PodcastDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest var podcastResults: FetchedResults<Podcast>
    @State private var episodes: [Episode] = []
    @State private var selectedEpisode: Episode? = nil
    var podcast: Podcast? { podcastResults.first }

    init(feedUrl: String) {
        _podcastResults = FetchRequest<Podcast>(
            entity: Podcast.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "feedUrl == %@", feedUrl),
            animation: .default
        )
    }

    var body: some View {
        ScrollView {
            if let podcast {
                VStack(alignment: .leading, spacing: 12) {
                    KFImage(URL(string:podcast.image ?? ""))
                        .resizable()
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                    
                    Text(podcast.title ?? "Podcast Title")
                        .titleSerif()
                    
                    Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
                        .textBody()
                        .lineLimit(3)
                    
                    Button(podcast.isSubscribed ? "Unsubscribe" : "Subscribe") {
                        podcast.isSubscribed.toggle()
                        try? context.save()
                    }

                    LazyVStack(alignment: .leading) {
                        ForEach(episodes, id: \.id) { episode in
                            EpisodeItem(episode: episode)
                                .lineLimit(3)
                                .onTapGesture {
                                    selectedEpisode = episode
                                }
                            Divider()
                        }
                    }
                    .sheet(item: $selectedEpisode) { episode in
                        EpisodeView(episode: episode)
                            .modifier(PPSheet())
                    }
                }
                .frame(maxWidth:.infinity)
                .padding()
                .onAppear {
                    episodes = (podcast.episode?.array as? [Episode]) ?? []

                    Task.detached(priority: .background) {
                        ColorTintManager.applyTintIfNeeded(to: podcast, in: context)
                    }
                }
            }
        }
    }
}
