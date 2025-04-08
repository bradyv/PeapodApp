//
//  TopPodcasts.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import SwiftUI
import Kingfisher
import CoreData

struct TopPodcasts: View {
    @EnvironmentObject var fetcher: PodcastFetcher
    var onTapPodcast: ((PodcastResult) -> Void)? = nil
    @State private var selectedPodcast: PodcastResult? = nil
    @Environment(\.managedObjectContext) private var context

    @State private var subscribedFeedURLs: Set<String> = []
    @State private var loadingFeedURLs: Set<String> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(fetcher.topPodcasts, id: \.id) { podcast in
                ZStack(alignment: .topTrailing) {
                    KFImage(URL(string: podcast.artworkUrl600))
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))

                    if let _ = onTapPodcast {
                        if subscribedFeedURLs.contains(podcast.feedUrl) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                                .padding(6)
                        } else if loadingFeedURLs.contains(podcast.feedUrl) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(width: 36, height: 36)
                                .padding(6)
                        } else {
                            Circle()
                                .frame(width: 36, height: 36)
                                .foregroundStyle(Color.red)
                                .overlay(Image(systemName: "plus").foregroundColor(.white))
                                .padding(6)
                                .onTapGesture {
                                    Task {
                                        loadingFeedURLs.insert(podcast.feedUrl)
                                        do {
                                            let _ = try await FeedLoader.loadAndCreatePodcast(from: podcast.feedUrl, in: context)
                                            subscribedFeedURLs.insert(podcast.feedUrl)
                                        } catch {
                                            print("❌ Subscription failed:", error.localizedDescription)
                                        }
                                        loadingFeedURLs.remove(podcast.feedUrl)
                                    }
                                }
                        }
                    }
                }
                .onTapGesture {
                    if onTapPodcast == nil {
                        selectedPodcast = podcast
                    }
                }
            }
        }
        .onAppear {
            if fetcher.topPodcasts.isEmpty {
                fetcher.fetchTopPodcasts()
            }
            loadSubscribedFeedURLs()
        }
        .sheet(item: $selectedPodcast) { podcast in
            PodcastDetailLoaderView(feedUrl: podcast.feedUrl)
                .modifier(PPSheet())
        }
    }

    private func loadSubscribedFeedURLs() {
        let fetchRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isSubscribed == YES")
        fetchRequest.propertiesToFetch = ["feedUrl"]

        do {
            let subscribed = try context.fetch(fetchRequest)
            let urls = subscribed.compactMap { $0.feedUrl }
            subscribedFeedURLs = Set(urls)
        } catch {
            print("Failed to fetch subscribed podcasts: \(error)")
        }
    }
}
