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
    
    static func fetchCuratedFeeds(completion: @escaping ([PodcastResult]) -> Void) {
        guard let url = URL(string: "https://bradyv.github.io/bvfeed.github.io/curated-feeds.json") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { data, _, _ in
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
                LogManager.shared.error("❌ Failed to decode curated podcasts: \(error)")
                completion([])
            }
        }.resume()
    }
    
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
                LogManager.shared.error("❌ Failed to decode top podcasts: \(error)")
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
                let validPodcasts = decoded.results.filter {
                    !$0.feedUrl.isEmpty
                }
                
                DispatchQueue.main.async {
                    completion(validPodcasts)
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
    
    // Regular initializer for manual creation
    init(feedUrl: String, trackName: String, artistName: String, artworkUrl600: String, trackId: Int) {
        self.feedUrl = feedUrl
        self.trackName = trackName
        self.artistName = artistName
        self.artworkUrl600 = artworkUrl600
        self.trackId = trackId
    }
    
    // Custom decoder that provides default empty string for missing feedUrl
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields normally
        trackName = try container.decode(String.self, forKey: .trackName)
        artistName = try container.decode(String.self, forKey: .artistName)
        artworkUrl600 = try container.decode(String.self, forKey: .artworkUrl600)
        trackId = try container.decode(Int.self, forKey: .trackId)
        
        // Decode feedUrl with default empty string if missing
        feedUrl = try container.decodeIfPresent(String.self, forKey: .feedUrl) ?? ""
    }
    
    private enum CodingKeys: String, CodingKey {
        case feedUrl, trackName, artistName, artworkUrl600, trackId
    }
}

enum PodcastLoader {
    
    static func loadFeed(from feedUrl: String, context: NSManagedObjectContext, completion: @escaping (Podcast?) -> Void) {
        // Convert HTTP to HTTPS for the feed URL itself
        let httpsUrl = forceHTTPS(feedUrl) ?? feedUrl
        
        guard let url = URL(string: httpsUrl) else {
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
                LogManager.shared.error("FeedKit error: \(error)")
                completion(nil)
            }
        }
    }
    
    // Helper function to convert HTTP URLs to HTTPS
    private static func forceHTTPS(_ urlString: String?) -> String? {
        guard let urlString = urlString else { return nil }
        return urlString.replacingOccurrences(of: "http://", with: "https://")
    }
    

    
    static func createOrUpdatePodcast(from rss: RSSFeed, feedUrl: String, context: NSManagedObjectContext) -> Podcast {
        let podcast = fetchOrCreatePodcast(feedUrl: feedUrl, context: context, title: rss.title, author: rss.iTunes?.iTunesAuthor)

        // Convert HTTP to HTTPS for podcast images
        podcast.image = podcast.image ??
                        forceHTTPS(rss.image?.url) ??
                        forceHTTPS(rss.iTunes?.iTunesImage?.attributes?.href) ??
                        forceHTTPS(rss.items?.first?.iTunes?.iTunesImage?.attributes?.href)

        podcast.podcastDescription = podcast.podcastDescription ?? rss.description ??
                                      rss.iTunes?.iTunesSummary ??
                                      rss.items?.first?.iTunes?.iTunesSummary ??
                                      rss.items?.first?.description

        if podcast.isInserted {
            podcast.isSubscribed = false
        }

        let existingEpisodes = (podcast.episode as? Set<Episode>) ?? []
        var existingEpisodesByGuid: [String: Episode] = [:]
        var existingEpisodesByTitleAndDate: [String: Episode] = [:]

        for episode in existingEpisodes {
            if let guid = episode.guid {
                existingEpisodesByGuid[guid] = episode
            } else if let title = episode.title, let airDate = episode.airDate {
                let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                existingEpisodesByTitleAndDate[key] = episode
            }
        }

        for item in rss.items ?? [] {
            guard let title = item.title else { continue }

            var existingEpisode: Episode?

            if let guid = item.guid?.value {
                existingEpisode = existingEpisodesByGuid[guid]
            } else if let pubDate = item.pubDate {
                let key = "\(title.lowercased())_\(pubDate.timeIntervalSince1970)"
                existingEpisode = existingEpisodesByTitleAndDate[key]
            }

            let episode = existingEpisode ?? Episode(context: context)

            if existingEpisode == nil {
                episode.id = UUID().uuidString
                episode.podcast = podcast
            }

            episode.guid = item.guid?.value
            episode.title = title
            
            // Convert HTTP to HTTPS for audio URLs
            episode.audio = forceHTTPS(item.enclosure?.attributes?.url)
            
            episode.episodeDescription = item.content?.contentEncoded ?? item.iTunes?.iTunesSummary ?? item.description
            episode.airDate = item.pubDate
            
            if let durationString = item.iTunes?.iTunesDuration {
                episode.duration = Double(durationString)
            }
            
            // Convert HTTP to HTTPS for episode images
            episode.episodeImage = forceHTTPS(item.iTunes?.iTunesImage?.attributes?.href) ?? podcast.image
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
