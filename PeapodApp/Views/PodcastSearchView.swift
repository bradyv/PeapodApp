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
    @State private var query = ""
    @State private var results: [PodcastResult] = []
    @State private var urlFeedPodcast: Podcast?
    @State private var topPodcasts: [PodcastResult] = []
    @State private var curatedFeeds: [PodcastResult] = []
    @State private var categoryPodcasts: [String: [PodcastResult]] = [:]
    @State private var hasSearched = false
    @State private var isLoadingUrlFeed = false
    @State private var urlFeedError: String?
    @State private var debounceWorkItem: DispatchWorkItem?
    @State private var selectedPodcast: PodcastResult? = nil
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    
    // Define categories with their genre IDs
    private let categories: [(name: String, icon: String, genreId: Int)] = [
        ("Arts", "paintpalette", 1301),
        ("Business", "briefcase", 1321),
        ("Comedy", "theatermasks", 1303),
        ("Education", "book", 1304),
        ("Fiction", "text.book.closed", 1483),
        ("Government", "building.columns", 1511),
        ("History", "clock", 1487),
        ("Health & Fitness", "heart", 1512),
        ("Kids & Family", "figure.2.and.child.holdinghands", 1305),
        ("Leisure", "leaf", 1502),
        ("Music", "music.note", 1310),
        ("News & Politics", "newspaper", 1489),
        ("Religion & Spirituality", "sparkles", 1314),
        ("Science", "flask", 1533),
        ("Society & Culture", "person.3", 1324),
        ("Sports", "sportscourt", 1545),
        ("Technology", "cpu", 1318),
        ("True Crime", "magnifyingglass", 1488),
        ("TV & Film", "film", 1309)
    ]

    var body: some View {
        ScrollView {
            if query.isEmpty {
                LazyVStack {
                    Text("Our Favorites")
                        .titleSerifMini()
                        .frame(maxWidth:.infinity, alignment:.leading)
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(curatedFeeds.enumerated()), id: \.1.id) { index, podcast in
                            NavigationLink {
                                PodcastDetailView(feedUrl: podcast.feedUrl)
                            } label: {
                                VStack {
                                    ArtworkView(url: podcast.artworkUrl600, size: nil, cornerRadius: 24)
                                }
                            }
                        }
                    }
                    
                    Spacer().frame(height:24)
                    
                    Text("Top Podcasts")
                        .titleSerifMini()
                        .frame(maxWidth:.infinity, alignment:.leading)
                    
                    Spacer().frame(height:8)
                    
                    // Category rows
                    VStack(spacing: 0) {
                        ForEach(categories, id: \.genreId) { category in
                            NavigationLink {
                                PodcastCategoryView(categoryName: category.name, genreId: category.genreId)
                            } label: {
                                CategoryRowItem(
                                    icon: category.icon,
                                    label: category.name,
                                    podcasts: categoryPodcasts[category.name] ?? []
                                )
                            }
                            Divider()
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
                                NavigationLink {
                                    PodcastDetailView(feedUrl:urlPodcast.feedUrl ?? "")
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
                                    } label: {
                                        HStack {
                                            ArtworkView(url: podcast.artworkUrl600, size: 44, cornerRadius: 12, tilt: false)
                                            
                                            VStack(alignment: .leading) {
                                                Text(podcast.title)
                                                    .titleCondensed()
                                                    .lineLimit(1)
                                                Text(podcast.author)
                                                    .textDetail()
                                                    .lineLimit(1)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            if podcast.isSubscribed(in: viewContext) {
                                                
                                                HStack(spacing:4) {
                                                    Image(systemName: "checkmark")
                                                        .textDetail()
                                                    
                                                    Text("Following")
                                                        .textDetail()
                                                }
                                                .padding(.horizontal).padding(.vertical,6)
                                                .background(Color.surface)
                                                .clipShape(Capsule())
                                            }
                                            
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
        .background(Color.background)
        .frame(maxWidth:.infinity, alignment:.leading)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Find a Podcast")
        .navigationTitle("Find a Podcast")
        .contentMargins(16, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onAppear {
            PodcastAPI.fetchCuratedFeeds { podcasts in
                self.curatedFeeds = podcasts
            }
            
            // Fetch top podcasts for each category
            for category in categories {
                PodcastAPI.fetchTopPodcastsByGenre(genreId: category.genreId, limit: 3) { podcasts in
                    DispatchQueue.main.async {
                        self.categoryPodcasts[category.name] = podcasts
                    }
                }
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

// New component for category rows
struct CategoryRowItem: View {
    let icon: String
    let label: String
    let podcasts: [PodcastResult]
    
    var body: some View {
        HStack(spacing:8) {
            Text(label)
                .foregroundStyle(Color.heading)
                .textBody()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyHStack(spacing:-4) {
                // Actual podcast artworks
                if !podcasts.isEmpty {
                    ForEach(Array(podcasts.prefix(3).enumerated()), id: \.offset) { index, podcast in
                        ArtworkView(url: podcast.artworkUrl600, size: 32, cornerRadius: 8, tilt: false)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.background, lineWidth: 2))
                    }
                }
            }
            
            Image(systemName: "chevron.right")
                .frame(width: 16, alignment: .trailing)
                .textBody()
                .opacity(0.25)
        }
        .padding(.vertical, 12)
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
