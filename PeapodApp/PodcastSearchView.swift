//
//  PodcastSearchView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import Kingfisher

struct PodcastSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @State private var query = ""
    @State private var results: [PodcastResult] = []
    @State private var topPodcasts: [PodcastResult] = []
    @State private var selectedPodcast: PodcastResult? = nil
    @State private var hasSearched = false
    @State private var debounceWorkItem: DispatchWorkItem?
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)

    var body: some View {
        VStack {
            VStack {
                SearchBox(
                    query: $query,
                    label: "Find a podcast",
                    onSubmit: {
                        search()
                    },
                    onCancel: {
                        query = ""
                        hasSearched = false
                        dismiss()
                    }
                )
            }
            .padding(.horizontal).padding(.top)
            
            if query.isEmpty {
                ScrollView {
                    FadeInView(delay: 0.2) {
                        Text("Top Podcasts")
                            .headerSection()
                            .frame(maxWidth:.infinity, alignment:.leading)
                    }
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(topPodcasts.enumerated()), id: \.1.id) { index, podcast in
                            VStack {
                                FadeInView(delay: Double(index) * 0.05) {
                                    KFImage(URL(string: podcast.artworkUrl600))
                                        .resizable()
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                                }
                            }
                            .onTapGesture {
                                selectedPodcast = podcast
                            }
                        }
                    }
                }
                .maskEdge(.bottom)
                .padding()
            } else {
                ScrollView {
                    if results.isEmpty && hasSearched {
                        FadeInView(delay: 0.2) {
                            VStack {
                                Text("No results for \(query)")
                                    .textBody()
                            }
                            .padding(.top,32)
                        }
                    } else if !results.isEmpty && hasSearched {
                        FadeInView(delay: 0.2) {
                            Text("Search Results")
                                .headerSection()
                                .frame(maxWidth:.infinity, alignment:.leading)
                                .padding(.horizontal)
                        }
                        
                        VStack(spacing: 8) {
                            ForEach(results, id: \.id) { podcast in
                                FadeInView(delay: 0.3) {
                                    HStack {
                                        KFImage(URL(string:podcast.artworkUrl600))
                                            .resizable()
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.15), lineWidth: 1))
                                        
                                        VStack(alignment: .leading) {
                                            Text(podcast.title)
                                                .titleCondensed()
                                                .lineLimit(1)
                                            Text(podcast.author)
                                                .textDetail()
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        Image(systemName: "chevron.right")
                                            .frame(width:12)
                                            .textDetail()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPodcast = podcast
                                    }
                                    
                                    Divider()
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .frame(maxWidth:.infinity)
            }
        }
        .onAppear {
            fetchTopPodcasts()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: query) { newValue in
            debounceWorkItem?.cancel()

            let task = DispatchWorkItem {
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                    results = []
                    hasSearched = false
                    return
                }
                search()
            }

            debounceWorkItem = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        }
        .sheet(item: $selectedPodcast) { podcast in
            PodcastDetailLoaderView(feedUrl: podcast.feedUrl)
                .modifier(PPSheet())
        }
    }

    func search() {
        guard let term = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=podcast&term=\(term)") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }
            if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
                DispatchQueue.main.async {
                    results = decoded.results
                    hasSearched = true
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
                fetchPodcastResults(for: ids)
            } catch {
                print("❌ Failed to decode top podcasts: \(error)")
            }
        }.resume()
    }
    
    func fetchPodcastResults(for ids: [String]) {
        let idString = ids.prefix(25).joined(separator: ",") // iTunes lookup limit is 200, but 25-50 is plenty
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(idString)") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }

            if let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) {
                DispatchQueue.main.async {
                    topPodcasts = decoded.results
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
