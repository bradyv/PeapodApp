//
//  PodcastDetailLoaderView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import FeedKit

struct PodcastDetailLoaderView: View {
    let feedUrl: String
    @Environment(\.managedObjectContext) private var context
    @State private var loadedPodcast: Podcast? = nil
    var namespace: Namespace.ID

    var body: some View {
        Group {
            if let podcast = loadedPodcast {
                PodcastDetailView(feedUrl: podcast.feedUrl ?? "", namespace: namespace)
            } else {
                VStack {
                    ProgressView("Loading...")
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
        .onAppear(perform: loadFeed)
    }

    private func loadFeed() {
        guard let url = URL(string: feedUrl) else { return }

        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    DispatchQueue.main.async {
                        let podcast = createOrUpdatePodcast(from: rss)
                        loadedPodcast = podcast
                    }
                }
            case .failure(let error):
                print("FeedKit error:", error)
            }
        }
    }

    private func createOrUpdatePodcast(from rss: RSSFeed) -> Podcast {
        let podcast = fetchOrCreatePodcast(feedUrl: feedUrl, context: context, title: rss.title, author: rss.iTunes?.iTunesAuthor)

        podcast.image = podcast.image ?? rss.image?.url ??
                        rss.iTunes?.iTunesImage?.attributes?.href ??
                        rss.items?.first?.iTunes?.iTunesImage?.attributes?.href

        podcast.podcastDescription = podcast.podcastDescription ?? rss.description ??
                                      rss.iTunes?.iTunesSummary ??
                                      rss.items?.first?.iTunes?.iTunesSummary ??
                                      rss.items?.first?.description

        if podcast.isInserted {
            podcast.isSubscribed = false
        }

        for item in rss.items ?? [] {
            let e = Episode(context: context)
            e.id = UUID().uuidString
            e.title = item.title
            e.audio = item.enclosure?.attributes?.url
            e.episodeDescription = item.content?.contentEncoded ?? item.iTunes?.iTunesSummary ?? item.description
            e.airDate = item.pubDate
            if let durationString = item.iTunes?.iTunesDuration {
                e.duration = Double(durationString)
            }
            e.episodeImage = item.iTunes?.iTunesImage?.attributes?.href
            e.podcast = podcast
        }

        try? context.save()
        return podcast
    }
}
