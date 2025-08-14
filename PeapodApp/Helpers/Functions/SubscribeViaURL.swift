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
        LogManager.shared.error("❌ Invalid URL: \(feedUrl)")
        completion?(false)
        return
    }

    context.perform {
        // Check for existing subscription
        let fetchRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "feedUrl == %@ AND isSubscribed == true", feedUrl)
        
        do {
            if let existingSubscribed = try context.fetch(fetchRequest).first {
                LogManager.shared.warning("⚠️ Already subscribed to: \(existingSubscribed.title ?? feedUrl)")
                DispatchQueue.main.async {
                    completion?(true) // Return true since they're already subscribed
                }
                return
            }
            
            // Check for any existing podcast (subscribed or not) and delete it
            let allExistingRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
            allExistingRequest.predicate = NSPredicate(format: "feedUrl == %@", feedUrl)
            
            if let existing = try context.fetch(allExistingRequest).first {
                // Delete all episodes for this podcast first
                let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                episodeRequest.predicate = NSPredicate(format: "podcastId == %@", existing.id ?? "")
                
                if let episodes = try? context.fetch(episodeRequest) {
                    for episode in episodes {
                        context.delete(episode)
                    }
                }
                
                context.delete(existing)
                LogManager.shared.info("🗑️ Deleted existing unsubscribed podcast and episodes for URL: \(feedUrl)")
            }
        } catch {
            LogManager.shared.error("❌ Error checking for existing podcast: \(error)")
            DispatchQueue.main.async {
                completion?(false)
            }
            return
        }

        // Parse feed using the new approach
        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    // Stay on the background context thread
                    context.perform {
                        // Create podcast metadata using the new approach
                        let podcast = createPodcastMetadataOnly(from: rss, feedUrl: feedUrl, context: context)
                        podcast.isSubscribed = true

                        // Save context before refreshing episodes
                        do {
                            try context.save()
                            LogManager.shared.info("✅ Created podcast: \(podcast.title ?? "Unknown")")
                        } catch {
                            LogManager.shared.error("❌ Error saving podcast: \(error)")
                            DispatchQueue.main.async {
                                completion?(false)
                            }
                            return
                        }

                        // Load initial episodes using EpisodeRefresher
                        EpisodeRefresher.loadInitialEpisodes(for: podcast, context: context) {
                            // Find the latest episode using podcastId query
                            let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                            episodeRequest.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
                            episodeRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
                            episodeRequest.fetchLimit = 1
                            
                            if let latestEpisode = try? context.fetch(episodeRequest).first {
                                // Add latest episode to queue using new playlist system
                                addEpisodeToPlaylist(latestEpisode, playlistName: "Queue")
                                LogManager.shared.info("🎵 Added latest episode to queue: \(latestEpisode.title ?? "Unknown")")
                            }
                            
                            LogManager.shared.info("✅ Subscribed to: \(rss.title ?? feedUrl)")
                            DispatchQueue.main.async {
                                completion?(true)
                            }
                        }
                    }
                } else {
                    LogManager.shared.error("❌ Failed to parse RSS feed from: \(feedUrl)")
                    DispatchQueue.main.async {
                        completion?(false)
                    }
                }
            case .failure(let error):
                LogManager.shared.error("❌ Feed parsing failed for \(feedUrl): \(error)")
                DispatchQueue.main.async {
                    completion?(false)
                }
            }
        }
    }
}

// Helper function to create podcast metadata (extracted from PodcastLoader)
private func createPodcastMetadataOnly(from rss: RSSFeed, feedUrl: String, context: NSManagedObjectContext) -> Podcast {
    let podcast = fetchOrCreatePodcast(feedUrl: feedUrl, context: context, title: rss.title, author: rss.iTunes?.iTunesAuthor)

    // Convert HTTP to HTTPS for podcast images
    if podcast.image == nil {
        podcast.image = forceHTTPS(rss.image?.url) ??
                       forceHTTPS(rss.iTunes?.iTunesImage?.attributes?.href) ??
                       forceHTTPS(rss.items?.first?.iTunes?.iTunesImage?.attributes?.href)
    }

    if podcast.podcastDescription == nil {
        podcast.podcastDescription = rss.description ??
                                    rss.iTunes?.iTunesSummary ??
                                    rss.items?.first?.iTunes?.iTunesSummary ??
                                    rss.items?.first?.description
    }

    if podcast.isInserted {
        podcast.isSubscribed = false
    }

    return podcast
}

// Helper function to convert HTTP URLs to HTTPS
private func forceHTTPS(_ urlString: String?) -> String? {
    guard let urlString = urlString else { return nil }
    return urlString.replacingOccurrences(of: "http://", with: "https://")
}

struct SubscribeTest: View {
    @State private var isLoading = false
    
    var body: some View {
        Button(action: {
            isLoading = true
            subscribeViaURL(feedUrl: "https://feeds.simplecast.com/3jYwX") { success in
                isLoading = false
                if success {
                    LogManager.shared.info("✅ Successfully subscribed!")
                } else {
                    LogManager.shared.error("❌ Failed to subscribe")
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
