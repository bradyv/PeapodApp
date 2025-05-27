//
//  SubscribeViaURL.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-27.
//

import SwiftUI
import CoreData
import FeedKit

func subscribeViaURL(feedUrl: String, completion: ((Bool) -> Void)? = nil) {
    let context = PersistenceController.shared.container.viewContext
    
    // Validate URL first
    guard let url = URL(string: feedUrl) else {
        print("❌ Invalid URL: \(feedUrl)")
        completion?(false)
        return
    }

    context.perform {
        // Check for existing subscription
        let fetchRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "feedUrl == %@ AND isSubscribed == true", feedUrl)
        
        do {
            if let existingSubscribed = try context.fetch(fetchRequest).first {
                print("⚠️ Already subscribed to: \(existingSubscribed.title ?? feedUrl)")
                DispatchQueue.main.async {
                    completion?(true) // Return true since they're already subscribed
                }
                return
            }
            
            // Check for any existing podcast (subscribed or not) and delete it
            let allExistingRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
            allExistingRequest.predicate = NSPredicate(format: "feedUrl == %@", feedUrl)
            
            if let existing = try context.fetch(allExistingRequest).first {
                context.delete(existing)
                print("🗑️ Deleted existing unsubscribed podcast for URL: \(feedUrl)")
            }
        } catch {
            print("❌ Error checking for existing podcast: \(error)")
            DispatchQueue.main.async {
                completion?(false)
            }
            return
        }

        // Parse feed
        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    // Stay on the background context thread
                    context.perform {
                        let podcast = PodcastLoader.createOrUpdatePodcast(from: rss, feedUrl: feedUrl, context: context)
                        podcast.isSubscribed = true

                        // 📢 DIAGNOSTIC PRINTS
                        print("RSS Title:", rss.title ?? "nil")
                        print("RSS iTunes Image:", rss.iTunes?.iTunesImage?.attributes?.href ?? "nil")
                        print("RSS Channel Image:", rss.image?.url ?? "nil")
                        print("RSS First Item Image:", rss.items?.first?.iTunes?.iTunesImage?.attributes?.href ?? "nil")

                        // 📢 MANUAL ASSIGN
                        let artworkUrl = rss.iTunes?.iTunesImage?.attributes?.href
                                      ?? rss.image?.url
                                      ?? rss.items?.first?.iTunes?.iTunesImage?.attributes?.href

                        podcast.image = artworkUrl

                        print("Assigned podcast.image:", podcast.image ?? "nil")

                        // Save context before refreshing episodes
                        do {
                            try context.save()
                        } catch {
                            print("❌ Error saving podcast: \(error)")
                            DispatchQueue.main.async {
                                completion?(false)
                            }
                            return
                        }

                        // Refresh episodes
                        EpisodeRefresher.refreshPodcastEpisodes(for: podcast, context: context) {
                            if let latest = (podcast.episode as? Set<Episode>)?
                                .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) })
                                .first {
                                toggleQueued(latest)
                            }
                            print("✅ Subscribed to: \(rss.title ?? feedUrl)")
                            DispatchQueue.main.async {
                                completion?(true)
                            }
                        }
                    }
                } else {
                    print("❌ Failed to parse RSS feed from: \(feedUrl)")
                    DispatchQueue.main.async {
                        completion?(false)
                    }
                }
            case .failure(let error):
                print("❌ Feed parsing failed for \(feedUrl): \(error)")
                DispatchQueue.main.async {
                    completion?(false)
                }
            }
        }
    }
}

struct SubscribeTest: View {
    @State private var isLoading = false
    
    var body: some View {
        Button(action: {
            isLoading = true
            subscribeViaURL(feedUrl: "https://feeds.simplecast.com/3jYwX") { success in
                isLoading = false
                if success {
                    print("✅ Successfully subscribed!")
                } else {
                    print("❌ Failed to subscribe")
                }
            }
        }) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Subscribing...")
                }
            } else {
                Text("Subscribe")
            }
        }
        .disabled(isLoading)
    }
}
