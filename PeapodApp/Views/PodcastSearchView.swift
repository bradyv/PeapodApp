//
//  PodcastSearchView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import Kingfisher
import FeedKit
import CoreData

struct PodcastSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FocusState private var isTextFieldFocused: Bool
    // Accept external search query binding
   @Binding var searchQuery: String
   
   // Use computed property for query that syncs with searchQuery
   private var query: String {
       get { searchQuery }
       set { searchQuery = newValue }
   }
    @State private var results: [PodcastResult] = []
    @State private var urlFeedPodcast: Podcast?
    @State private var topPodcasts: [PodcastResult] = []
    @State private var curatedFeeds: [PodcastResult] = []
    @State private var hasSearched = false
    @State private var isLoadingUrlFeed = false
    @State private var urlFeedError: String?
    @State private var debounceWorkItem: DispatchWorkItem?
    @State private var selectedPodcast: PodcastResult? = nil
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)

    var body: some View {
        ScrollView {
            if query.isEmpty {
                Text("Our Favorites")
                    .titleSerifMini()
                    .frame(maxWidth:.infinity, alignment:.leading)
                
                Text("What we're listening to.")
                    .textDetail()
                    .frame(maxWidth:.infinity, alignment:.leading)
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(curatedFeeds.enumerated()), id: \.1.id) { index, podcast in
                        NavigationLink {
                            PodcastDetailView(feedUrl: podcast.feedUrl)
//                            selectedPodcast = podcast
                        } label: {
                            VStack {
                                FadeInView(delay: Double(index) * 0.05) {
                                    ArtworkView(url: podcast.artworkUrl600, size: nil, cornerRadius: 24)
                                }
                            }
                        }
                    }
                }
                
                Spacer().frame(height:24)
                
                Text("Top Podcasts")
                    .titleSerifMini()
                    .frame(maxWidth:.infinity, alignment:.leading)
                
                Text("What the world is listening to.")
                    .textDetail()
                    .frame(maxWidth:.infinity, alignment:.leading)
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(topPodcasts.enumerated()), id: \.1.id) { index, podcast in
                        NavigationLink {
                            PodcastDetailView(feedUrl: podcast.feedUrl)
//                            selectedPodcast = podcast
                        } label: {
                            VStack {
                                FadeInView(delay: Double(index) * 0.05) {
                                    ArtworkView(url: podcast.artworkUrl600, size: nil, cornerRadius: 24)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack {
                    // Show loading indicator for URL feeds
                    if isLoadingUrlFeed {
                        FadeInView(delay: 0.1) {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading podcast feed...")
                                    .textBody()
                            }
                            .frame(maxWidth:.infinity)
                            .padding()
                        }
                    }
                    
                    // Show URL feed error if any
                    if let error = urlFeedError {
                        FadeInView(delay: 0.2) {
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .textBody()
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth:.infinity)
                            .padding()
                        }
                    }
                    
                    // Show URL feed result if available
                    if let urlPodcast = urlFeedPodcast {
                        FadeInView(delay: 0.2) {
                            Text("Podcast Feed")
                                .headerSection()
                                .frame(maxWidth:.infinity, alignment:.leading)
                                .padding(.horizontal)
                        }
                        
                        VStack(spacing: 8) {
                            FadeInView(delay: 0.3) {
                                Button {
                                    let podcastResult = PodcastResult(
                                        feedUrl: urlPodcast.feedUrl ?? "",
                                        trackName: urlPodcast.title ?? "Unknown Podcast",
                                        artistName: urlPodcast.author ?? "Unknown Author",
                                        artworkUrl600: urlPodcast.image ?? "",
                                        trackId: urlPodcast.id?.hashValue ?? 0
                                    )
                                    selectedPodcast = podcastResult
                                } label: {
                                    HStack {
                                        ArtworkView(url: urlPodcast.image ?? "", size: 44, cornerRadius: 12, tilt: false)
                                        
                                        VStack(alignment: .leading) {
                                            Text(urlPodcast.title ?? "Unknown Podcast")
                                                .titleCondensed()
                                                .lineLimit(1)
                                            Text(urlPodcast.author ?? "Unknown Author")
                                                .textDetail()
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        Image(systemName: "chevron.right")
                                            .frame(width:12)
                                            .textDetail()
                                    }
                                    .contentShape(Rectangle())
                                }
                                
                                Divider()
                            }
                        }
                        .frame(maxWidth:.infinity)
                    }
                    
                    // Show regular search results
                    if results.isEmpty && hasSearched && urlFeedPodcast == nil && !isLoadingUrlFeed && urlFeedError == nil {
                        FadeInView(delay: 0.2) {
                            VStack {
                                Text("No results for \(query)")
                                    .textBody()
                            }
                            .frame(maxWidth:.infinity)
                            .padding(.top,32)
                        }
                    } else if !results.isEmpty && hasSearched {
                        FadeInView(delay: 0.2) {
                            Text("Search Results")
                                .titleSerifMini()
                                .frame(maxWidth:.infinity, alignment:.leading)
                        }
                        
                        VStack(spacing: 8) {
                            ForEach(results, id: \.id) { podcast in
                                FadeInView(delay: 0.3) {
                                    NavigationLink {
                                        PodcastDetailView(feedUrl: podcast.feedUrl)
//                                        selectedPodcast = podcast
                                    } label: {
                                        HStack {
                                            ArtworkView(url: podcast.artworkUrl600, size: 44, cornerRadius: 12, tilt: false)
                                            
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
                                    }
                                    
                                    Divider()
                                }
                            }
                        }
                        .frame(maxWidth:.infinity)
                    }
                }
                .frame(maxWidth:.infinity)
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .navigationBarTitleDisplayMode(.large)
        .contentMargins(16, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onAppear {
            PodcastAPI.fetchCuratedFeeds { podcasts in
                self.curatedFeeds = podcasts
            }
            PodcastAPI.fetchTopPodcasts { podcasts in
                self.topPodcasts = podcasts
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: query) { newValue in
            debounceWorkItem?.cancel()
            
            let task = DispatchWorkItem {
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                    results = []
                    urlFeedPodcast = nil
                    urlFeedError = nil
                    hasSearched = false
                    return
                }
                search()
            }
            
            debounceWorkItem = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        }
        .sheet(item: $selectedPodcast) { podcastResult in
            PodcastDetailView(feedUrl: podcastResult.feedUrl)
                .modifier(PPSheet())
        }
    }

    func search() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        
        // Check if the query looks like a URL
        if isValidURL(trimmedQuery) {
            searchByURL(trimmedQuery)
        } else {
            searchByTerm(trimmedQuery)
        }
    }
    
    private func isValidURL(_ string: String) -> Bool {
        // Check for common URL patterns
        let urlPattern = #"^https?://.*"#
        let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: string.utf16.count)
        return regex?.firstMatch(in: string, options: [], range: range) != nil
    }
    
    private func searchByURL(_ urlString: String) {
        isLoadingUrlFeed = true
        urlFeedPodcast = nil
        urlFeedError = nil
        results = []
        hasSearched = true
        
        // Use the same pattern as WelcomeView
        PodcastLoader.loadFeed(from: urlString, context: viewContext) { loadedPodcast in
            DispatchQueue.main.async {
                isLoadingUrlFeed = false
                
                if let podcast = loadedPodcast {
                    urlFeedPodcast = podcast
                    LogManager.shared.info("✅ Successfully loaded podcast feed: \(podcast.title ?? "Unknown")")
                } else {
                    urlFeedError = "Unable to load podcast feed from this URL. Please check that it's a valid RSS feed."
                    LogManager.shared.error("❌ Failed to load podcast from URL: \(urlString)")
                }
            }
        }
    }
    
    private func searchByTerm(_ term: String) {
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=podcast&term=\(encodedTerm)") else { return }

        // Reset URL result when doing term search
        urlFeedPodcast = nil
        urlFeedError = nil
        
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
}


struct CuratedFeedView: View {
    @State private var curatedFeeds: [PodcastResult] = []
    let url: String
    let description: String
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack {
                KFImage(URL(string:url))
                    .resizable()
                    .frame(width: 270, height: 270)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                       startPoint: .init(x:0.5,y:0.4), endPoint: .init(x:0.5,y:0.8))
                    )
                    .allowsHitTesting(false)
                Spacer()
            }
            
            Text(description)
                .foregroundStyle(.white)
                .textBody()
        }
        .frame(width: 270, height: 320)
        .background(
            KFImage(URL(string:url))
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .scaleEffect(x: 1, y: -1)
                .blur(radius: 44)
                .opacity(0.5)
        )
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .glassEffect(in: .rect(cornerRadius:32))
    }
}
