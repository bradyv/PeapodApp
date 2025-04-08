//
//  FeedLoader.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import Foundation
import FeedKit
import CoreData

struct FeedLoader {
    static func loadAndCreatePodcast(from feedUrl: String, in context: NSManagedObjectContext) async throws -> Podcast {
        guard let url = URL(string: feedUrl) else {
            throw URLError(.badURL)
        }

        return try await withCheckedThrowingContinuation { continuation in
            FeedParser(URL: url).parseAsync { result in
                switch result {
                case .success(let feed):
                    if let rss = feed.rssFeed {
                        let podcast = Podcast(context: context)
                        podcast.id = UUID().uuidString
                        podcast.feedUrl = feedUrl
                        podcast.title = rss.title ?? "Untitled"
                        podcast.author = rss.iTunes?.iTunesAuthor ?? "Unknown"
                        podcast.image = rss.image?.url
                        podcast.podcastDescription = rss.description
                        podcast.isSubscribed = true

                        var allEpisodes: [Episode] = []

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
                            allEpisodes.append(e)
                        }

                        // 🔥 Automatically queue the latest episode if available
                        if let latest = allEpisodes
                            .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) })
                            .first {
                            latest.isQueued = true
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

                        do {
                            try context.save()
                            Task.detached(priority: .background) {
                                await ColorTintManager.applyTintIfNeeded(to: podcast, in: context)
                            }
                            continuation.resume(returning: podcast)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    } else {
                        continuation.resume(throwing: NSError(domain: "No RSS feed found", code: -1))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
