//
//  PodcastFetcher.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-27.
//

import Foundation
import FeedKit
import CoreData

// Keep PodcastAPI unchanged - it's for iTunes search, not feed parsing
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

// Simplified PodcastLoader that delegates to PodcastManager
enum PodcastLoader {
    
    static func loadFeed(from feedUrl: String, context: NSManagedObjectContext, completion: @escaping (Podcast?) -> Void) {
        PodcastManager.loadPodcastFromFeed(feedUrl: feedUrl, context: context, completion: completion)
    }
}
