//
//  PodcastFetcher.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-27.
//

import Foundation
import FeedKit
import CoreData

enum PodcastAPI {
    
    static func fetchTopPodcasts(limit: Int = 21, completion: @escaping ([PodcastResult]) -> Void) {
        guard let url = URL(string: "https://itunes.apple.com/us/rss/toppodcasts/limit=\(limit)/json") else {
            completion([])
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else {
                completion([])
                return
            }

            struct FeedResponse: Codable {
                struct Feed: Codable {
                    struct Entry: Codable {
                        struct ID: Codable {
                            let attributes: Attributes
                            struct Attributes: Codable {
                                let imID: String
                                enum CodingKeys: String, CodingKey { case imID = "im:id" }
                            }
                        }
                        let id: ID
                    }
                    let entry: [Entry]
                }
                let feed: Feed
            }

            do {
                let decoded = try JSONDecoder().decode(FeedResponse.self, from: data)
                let ids = decoded.feed.entry.map { $0.id.attributes.imID }
                fetchPodcastResults(for: ids, completion: completion)
            } catch {
                print("❌ Failed to decode top podcasts: \(error)")
                completion([])
            }
        }.resume()
    }
    
    static func fetchPodcastResults(for ids: [String], completion: @escaping ([PodcastResult]) -> Void) {
        let idString = ids.joined(separator: ",")
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(idString)") else {
            completion([])
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else {
                completion([])
                return
            }

            if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
                DispatchQueue.main.async {
                    completion(decoded.results)
                }
            } else {
                completion([])
            }
        }.resume()
    }
}

struct SearchResponse: Codable {
    let results: [PodcastResult]
}

struct PodcastResult: Codable, Identifiable {
    let feedUrl: String
    let trackName: String
    let artistName: String
    let artworkUrl600: String
    let trackId: Int

    var id: String { "\(trackId)" }
    var title: String { trackName }
    var author: String { artistName }
}


enum PodcastLoader {
    
    static func loadFeed(from feedUrl: String, context: NSManagedObjectContext, completion: @escaping (Podcast?) -> Void) {
        guard let url = URL(string: feedUrl) else {
            completion(nil)
            return
        }

        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    DispatchQueue.main.async {
                        let podcast = createOrUpdatePodcast(from: rss, feedUrl: feedUrl, context: context)
                        completion(podcast)
                    }
                } else {
                    completion(nil)
                }
            case .failure(let error):
                print("FeedKit error:", error)
                completion(nil)
            }
        }
    }
    
    static func createOrUpdatePodcast(from rss: RSSFeed, feedUrl: String, context: NSManagedObjectContext) -> Podcast {
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

        let existingTitles = Set((podcast.episode as? Set<Episode>)?.compactMap { $0.title } ?? [])

        for item in rss.items ?? [] {
            guard let title = item.title, !existingTitles.contains(title) else { continue }

            let e = Episode(context: context)
            e.id = UUID().uuidString
            e.title = title
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
    
    private static func fetchOrCreatePodcast(feedUrl: String, context: NSManagedObjectContext, title: String?, author: String?) -> Podcast {
        let request = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "feedUrl == %@", feedUrl)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            return existing
        } else {
            let newPodcast = Podcast(context: context)
            newPodcast.id = UUID().uuidString
            newPodcast.feedUrl = feedUrl
            newPodcast.title = title
            newPodcast.author = author
            return newPodcast
        }
    }
}
