//
//  OPMLImportManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-08-09.
//

import SwiftUI
import CoreData

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
        
        // Use a continuation to bridge the callback-based PodcastLoader to async/await
        await withCheckedContinuation { continuation in
            context.perform {
                PodcastLoader.loadFeed(from: feedUrl, context: context) { loadedPodcast in
                    if let podcast = loadedPodcast {
                        // Subscribe to the podcast
                        podcast.isSubscribed = true
                        
                        // Queue the latest episode
                        if let latestEpisode = (podcast.episode as? Set<Episode>)?
                            .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) })
                            .first {
                            toggleQueued(latestEpisode)
                        }
                        
                        // Save the context
                        try? context.save()
                        
                        Task { @MainActor in
                            self.processedPodcasts += 1
                            self.progress = Double(self.processedPodcasts) / Double(self.totalPodcasts)
                        }
                    } else {
                        LogManager.shared.error("Failed to load podcast from URL: \(feedUrl)")
                        Task { @MainActor in
                            self.processedPodcasts += 1
                            self.progress = Double(self.processedPodcasts) / Double(self.totalPodcasts)
                        }
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
}
