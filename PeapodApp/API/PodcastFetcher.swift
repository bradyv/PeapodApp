//
//  PodcastFetcher.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import Foundation
import SwiftUI

class PodcastFetcher: ObservableObject {
    @Published var query: String = ""
    @Published var results: [PodcastResult] = []
    @Published var topPodcasts: [PodcastResult] = []

    func search() {
        guard let term = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=podcast&term=\(term)") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }
            if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.results = decoded.results
                }
            }
        }.resume()
    }

    func fetchTopPodcasts() {
        guard let url = URL(string: "https://itunes.apple.com/us/rss/toppodcasts/limit=21/json") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }

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
                self.fetchPodcastResults(for: ids)
            } catch {
                print("❌ Failed to decode top podcasts: \(error)")
            }
        }.resume()
    }

    private func fetchPodcastResults(for ids: [String]) {
        let idString = ids.prefix(25).joined(separator: ",")
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(idString)") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }

            if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.topPodcasts = decoded.results
                }
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
