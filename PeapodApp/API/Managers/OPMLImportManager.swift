//
//  OPMLImportManager.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-08-09.
//

import SwiftUI
import CoreData
import FeedKit

// MARK: - OPML Parser
struct OPMLParser {
    struct OPMLOutline {
        let title: String?
        let xmlUrl: String?
        let htmlUrl: String?
        let type: String?
    }
    
    static func parseOPML(from xmlString: String) -> [OPMLOutline] {
        var outlines: [OPMLOutline] = []
        
        guard let data = xmlString.data(using: .utf8) else { return outlines }
        
        let parser = XMLParser(data: data)
        let delegate = OPMLParserDelegate()
        parser.delegate = delegate
        parser.parse()
        
        return delegate.outlines
    }
}

// MARK: - XML Parser Delegate
private class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var outlines: [OPMLParser.OPMLOutline] = []
    private var currentElement = ""
    private var currentAttributes: [String: String] = [:]
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentAttributes = attributeDict
        
        if elementName == "outline" {
            // Check if this is a podcast feed (has xmlUrl)
            if let xmlUrl = attributeDict["xmlUrl"], !xmlUrl.isEmpty {
                let outline = OPMLParser.OPMLOutline(
                    title: attributeDict["title"] ?? attributeDict["text"],
                    xmlUrl: xmlUrl,
                    htmlUrl: attributeDict["htmlUrl"],
                    type: attributeDict["type"]
                )
                outlines.append(outline)
            }
        }
    }
}

// MARK: - OPML Import Manager
class OPMLImportManager: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var currentStatus: String = "Importing your subscriptions..."
    @Published var isComplete: Bool = false
    @Published var totalPodcasts: Int = 0
    @Published var processedPodcasts: Int = 0
    
    func importOPML(xmlString: String, context: NSManagedObjectContext) {
        Task {
            await performImport(xmlString: xmlString, context: context)
        }
    }
    
    @MainActor
    private func performImport(xmlString: String, context: NSManagedObjectContext) async {
        // Parse OPML
        let outlines = OPMLParser.parseOPML(from: xmlString)
        let feedUrls = outlines.compactMap { $0.xmlUrl }.filter { !$0.isEmpty }
        
        totalPodcasts = feedUrls.count
        
        guard totalPodcasts > 0 else {
            currentStatus = "No podcasts found in your file."
            isComplete = true
            return
        }
        
        currentStatus = "Found \(totalPodcasts) podcasts."
        
        // Create a background context for the import
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Process feeds with concurrency control
        await processFeedsWithConcurrency(feedUrls: feedUrls, context: backgroundContext)
        
        currentStatus = "Added \(processedPodcasts) podcasts to your library."
        isComplete = true
        
        UserDefaults.standard.set(true, forKey: "OPMLImported")
        NSUbiquitousKeyValueStore.default.set(true, forKey: "OPMLImported")
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    private func processFeedsWithConcurrency(feedUrls: [String], context: NSManagedObjectContext) async {
        let semaphore = DispatchSemaphore(value: 3) // Limit to 3 concurrent requests
        
        return await withTaskGroup(of: Void.self) { group in
            for (index, feedUrl) in feedUrls.enumerated() {
                group.addTask {
                    semaphore.wait()
                    defer { semaphore.signal() }
                    
                    await self.processSingleFeed(
                        feedUrl: feedUrl,
                        index: index,
                        context: context
                    )
                }
            }
        }
    }
    
    private func processSingleFeed(feedUrl: String, index: Int, context: NSManagedObjectContext) async {
        await MainActor.run {
            currentStatus = "Loading podcast \(index + 1) of \(totalPodcasts)"
        }
        
        // Parse feed directly instead of using deprecated PodcastLoader.loadFeed
        guard let url = URL(string: feedUrl) else {
            LogManager.shared.error("Invalid URL: \(feedUrl)")
            await incrementProgress()
            return
        }
        
        // Use a continuation to bridge the callback-based FeedParser to async/await
        await withCheckedContinuation { continuation in
            FeedParser(URL: url).parseAsync { result in
                context.perform {
                    switch result {
                    case .success(let feed):
                        if let rss = feed.rssFeed {
                            // Create podcast metadata using new approach
                            let podcast = self.createPodcastMetadataOnly(from: rss, feedUrl: feedUrl, context: context)
                            podcast.isSubscribed = true
                            
                            // Save podcast first
                            do {
                                try context.save()
                                LogManager.shared.info("✅ Created podcast: \(podcast.title ?? feedUrl)")
                                
                                // Load initial episodes
                                EpisodeRefresher.loadInitialEpisodes(for: podcast, context: context) {
                                    // Find latest episode and add to queue
                                    self.queueLatestEpisode(for: podcast, context: context)
                                    
                                    Task { @MainActor in
                                        self.incrementProgressSync()
                                    }
                                    continuation.resume()
                                }
                            } catch {
                                LogManager.shared.error("❌ Error saving podcast: \(error)")
                                Task { @MainActor in
                                    self.incrementProgressSync()
                                }
                                continuation.resume()
                            }
                        } else {
                            LogManager.shared.error("Failed to parse RSS for: \(feedUrl)")
                            Task { @MainActor in
                                self.incrementProgressSync()
                            }
                            continuation.resume()
                        }
                        
                    case .failure(let error):
                        LogManager.shared.error("Feed parsing failed for \(feedUrl): \(error)")
                        Task { @MainActor in
                            self.incrementProgressSync()
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    // Helper function to create podcast metadata (same as in SubscribeViaURL)
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
    
    private func fetchOrCreatePodcast(feedUrl: String, context: NSManagedObjectContext, title: String?, author: String?) -> Podcast {
        let normalizedUrl = feedUrl.normalizeURL()
        
        let request = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "feedUrl == %@", normalizedUrl)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        } else {
            let podcast = Podcast(context: context)
            podcast.feedUrl = normalizedUrl
            podcast.id = UUID().uuidString
            podcast.title = title
            podcast.author = author
            return podcast
        }
    }
    
    // Helper function to convert HTTP URLs to HTTPS
    private func forceHTTPS(_ urlString: String?) -> String? {
        guard let urlString = urlString else { return nil }
        return urlString.replacingOccurrences(of: "http://", with: "https://")
    }
    
    // Helper to queue latest episode using new playlist system
    private func queueLatestEpisode(for podcast: Podcast, context: NSManagedObjectContext) {
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        episodeRequest.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        episodeRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        episodeRequest.fetchLimit = 1
        
        if let latestEpisode = try? context.fetch(episodeRequest).first {
            // Add to queue using new playlist system
            addEpisodeToPlaylist(latestEpisode, playlistName: "Queue")
            LogManager.shared.info("🎵 Added latest episode to queue: \(latestEpisode.title ?? "Unknown")")
        }
    }
    
    @MainActor
    private func incrementProgress() async {
        processedPodcasts += 1
        progress = Double(processedPodcasts) / Double(totalPodcasts)
    }
    
    private func incrementProgressSync() {
        processedPodcasts += 1
        progress = Double(processedPodcasts) / Double(totalPodcasts)
    }
}
