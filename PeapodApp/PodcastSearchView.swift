//
//  PodcastSearchView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import Kingfisher

struct PodcastSearchView: View {
    @FocusState private var isTextFieldFocused: Bool
    @State private var query = ""
    @State private var results: [PodcastResult] = []
    @State private var selectedPodcast: PodcastResult? = nil

    var body: some View {
        VStack {
            VStack {
                HStack {
                    Image(systemName: "plus.magnifyingglass")
                        .resizable()
                        .frame(width: 12, height: 12)
                        .opacity(0.35)
                    TextField("Search or paste URL", text: $query)
                        .focused($isTextFieldFocused)
                        .textRow()
                        .onSubmit {
                            search()
                        }
                    
                    
                    if !query.isEmpty {
                        Button(action: {
                            query = ""
                            isTextFieldFocused = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.surface)
                .cornerRadius(44)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isTextFieldFocused = true
                    }
                }
            }
            .padding()
            
            ScrollView {
                ForEach(results, id: \.id) { podcast in
                    HStack {
                        KFImage(URL(string:podcast.artworkUrl600))
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.15), lineWidth: 1))
                        
                        VStack(alignment: .leading) {
                            Text(podcast.title)
                                .font(.headline)
                            Text(podcast.author)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                    .onTapGesture {
                        selectedPodcast = podcast
                    }
                }
            }
            .frame(maxWidth:.infinity)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
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
