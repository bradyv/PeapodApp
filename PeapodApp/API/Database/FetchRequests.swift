//
//  FetchRequests.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-28.
//

import SwiftUI
import CoreData

extension Episode {
    // Queue episodes: use helper function instead of direct fetch
    static func queueFetchRequest() -> NSFetchRequest<Episode> {
        // This will be replaced by getQueuedEpisodes(context:)
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "FALSEPREDICATE") // Empty result, use helper function
        return request
    }
    
    // Latest episodes from subscribed podcasts
    static func latestEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        // Note: This should be used with context-specific podcast ID fetching
        request.predicate = NSPredicate(format: "TRUEPREDICATE") // Placeholder - use helper function
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchBatchSize = 20
        return request
    }
    
    // Unplayed episodes: need to check if NOT in "Played" using boolean approach
    static func unplayedEpisodesRequest(context: NSManagedObjectContext) -> NSFetchRequest<Episode> {
        let subscribedPodcastIds = getSubscribedPodcastIds(context: context)
        
        let request = Episode.fetchRequest()
        
        guard !subscribedPodcastIds.isEmpty else {
            request.predicate = NSPredicate(format: "FALSEPREDICATE")
            return request
        }
        
        // Get played episode IDs using boolean approach
        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
        playbackRequest.predicate = NSPredicate(format: "isPlayed == YES")
        let playedPlaybackStates = (try? context.fetch(playbackRequest)) ?? []
        let playedIds = playedPlaybackStates.compactMap { $0.episodeId }
        
        let subscribedPredicate = NSPredicate(format: "podcastId IN %@", subscribedPodcastIds)
        
        if playedIds.isEmpty {
            // No played episodes, so all subscribed episodes are unplayed
            request.predicate = subscribedPredicate
        } else {
            // Exclude played episodes
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                subscribedPredicate,
                NSPredicate(format: "NOT (id IN %@)", playedIds)
            ])
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchBatchSize = 20
        return request
    }
    
    // Old episodes: episodes from unsubscribed podcasts that aren't saved in any boolean state
    static func oldEpisodesRequest(context: NSManagedObjectContext) -> NSFetchRequest<Episode> {
        let unsubscribedPodcastIds = getUnsubscribedPodcastIds(context: context)
        
        // Get all episode IDs that have ANY playback state (queued, played, or favorited)
        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
        playbackRequest.predicate = NSPredicate(format: "isQueued == YES OR isPlayed == YES OR isFav == YES")
        let savedPlaybackStates = (try? context.fetch(playbackRequest)) ?? []
        let savedEpisodeIds = savedPlaybackStates.compactMap { $0.episodeId }
        
        let request = Episode.fetchRequest()
        
        guard !unsubscribedPodcastIds.isEmpty else {
            request.predicate = NSPredicate(format: "FALSEPREDICATE")
            return request
        }
        
        let unsubscribedPredicate = NSPredicate(format: "podcastId IN %@", unsubscribedPodcastIds)
        
        if savedEpisodeIds.isEmpty {
            request.predicate = unsubscribedPredicate
        } else {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                unsubscribedPredicate,
                NSPredicate(format: "NOT (id IN %@)", savedEpisodeIds)
            ])
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.id, ascending: true)]
        request.fetchBatchSize = 20
        return request
    }
}

extension Podcast {
    static func subscriptionsFetchRequest() -> NSFetchRequest<Podcast> {
        let request = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        // Sort at database level, not in SwiftUI
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Podcast.title, ascending: true)]
        request.fetchBatchSize = 20
        
        // Scroll performance optimizations
        request.returnsObjectsAsFaults = false // Avoid faulting during scroll
        request.includesPropertyValues = true
        
        return request
    }
    
    // Moved from ActivityView.swift
    static func topPlayedRequest() -> NSFetchRequest<Podcast> {
        let request = NSFetchRequest<Podcast>(entityName: "Podcast")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Podcast.playedSeconds, ascending: false)]
        request.fetchLimit = 3
        return request
    }
    
    // NEW: Count unique podcasts in database
    static func uniquePodcastCount(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<Podcast>(entityName: "Podcast")
        request.resultType = .countResultType
        return try context.count(for: request)
    }
    
    // NEW: Count total podcasts in database (same as unique count for podcasts)
    static func totalPodcastCount(in context: NSManagedObjectContext) throws -> Int {
        return try uniquePodcastCount(in: context)
    }
    
    // Moved from ActivityView.swift
    static func totalPlayedDuration(in context: NSManagedObjectContext) async throws -> Double {
        let request = NSFetchRequest<NSDictionary>(entityName: "Podcast")
        request.resultType = .dictionaryResultType

        let sumExpression = NSExpressionDescription()
        sumExpression.name = "totalPlayedDuration"
        sumExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "playedSeconds")])
        sumExpression.expressionResultType = .doubleAttributeType

        request.propertiesToFetch = [sumExpression]

        let results = try context.fetch(request)
        let total = results.first?["totalPlayedDuration"] as? Double ?? 0.0
        return total
    }
    
    // Moved from ActivityView.swift
    static func totalSubscribedCount(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSNumber>(entityName: "Podcast")
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        request.resultType = .countResultType

        return try context.count(for: request)
    }

    // Moved from ActivityView.swift
    static func totalPlayCount(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSDictionary>(entityName: "Podcast")
        request.resultType = .dictionaryResultType

        let sumExpression = NSExpressionDescription()
        sumExpression.name = "totalPlayCount"
        sumExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "playCount")])
        sumExpression.expressionResultType = .integer32AttributeType

        request.propertiesToFetch = [sumExpression]

        let results = try context.fetch(request)
        return results.first?["totalPlayCount"] as? Int ?? 0
    }
    
    // Moved from ActivityView.swift
    var formattedPlayedHours: String {
        let hours = playedSeconds / 3600
        let rounded = (hours * 10).rounded() / 10  // round to 1 decimal place

        if rounded == floor(rounded) {
            let whole = Int(rounded)
            return "\(whole) " + (whole == 1 ? "hour" : "hours")
        } else {
            return String(format: "%.1f hours", rounded)
        }
    }
}

extension User {
    static func userSinceRequest(date: Date) -> NSFetchRequest<User> {
        let request = User.fetchRequest()
        request.predicate = NSPredicate(format: "userSince == %@", date as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \User.userSince, ascending: true)]
        return request
    }
    
    static func userTypeRequest(type: String) -> NSFetchRequest<User> {
        let request = User.fetchRequest()
        request.predicate = NSPredicate(format: "userType == %@", type)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \User.userType, ascending: true)]
        return request
    }
}

// MARK: - Helper Functions for Predicates

func getSubscribedPodcastIds(context: NSManagedObjectContext) -> [String] {
    let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
    request.predicate = NSPredicate(format: "isSubscribed == YES")
    
    do {
        let podcasts = try context.fetch(request)
        return podcasts.compactMap { $0.id }
    } catch {
        LogManager.shared.error("Error fetching subscribed podcast IDs: \(error)")
        return []
    }
}

func getUnsubscribedPodcastIds(context: NSManagedObjectContext) -> [String] {
    let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
    request.predicate = NSPredicate(format: "isSubscribed == NO")
    
    do {
        let podcasts = try context.fetch(request)
        return podcasts.compactMap { $0.id }
    } catch {
        LogManager.shared.error("Error fetching unsubscribed podcast IDs: \(error)")
        return []
    }
}

// MARK: - App Statistics Helper

struct AppStatistics {
    let podcastCount: Int
    let totalPlayedSeconds: Double
    let subscribedCount: Int
    let playCount: Int
    
    static func load(from context: NSManagedObjectContext) async throws -> AppStatistics {
        let podcasts = try Podcast.totalPodcastCount(in: context)
        let playedSeconds = try await Podcast.totalPlayedDuration(in: context)
        let subscribed = try Podcast.totalSubscribedCount(in: context)
        let plays = try Podcast.totalPlayCount(in: context)
        
        return AppStatistics(
            podcastCount: podcasts,
            totalPlayedSeconds: playedSeconds,
            subscribedCount: subscribed,
            playCount: plays
        )
    }
}

struct WeeklyListeningData {
    let dayOfWeek: Int
    let count: Int
    let percentage: Double
    let dayAbbreviation: String
}

// MARK: - Usage Examples

// Episode examples
// @FetchRequest(fetchRequest: Episode.queueFetchRequest(), animation: .interactiveSpring())
// var queue: FetchedResults<Episode>

// @FetchRequest(fetchRequest: Episode.longestPlayedEpisodeRequest(), animation: .default)
// var longestEpisode: FetchedResults<Episode>

// Podcast examples
// @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest(), animation: .interactiveSpring)
// var subscriptions: FetchedResults<Podcast>

// @FetchRequest(fetchRequest: Podcast.topPlayedRequest(), animation: .default)
// var topPodcasts: FetchedResults<Podcast>

// Usage for counting and analytics (in a view or view model):
// let uniqueCount = try Podcast.uniquePodcastCount(in: viewContext)
// let (dayOfWeek, count) = try Episode.mostPopularListeningDay(in: viewContext)
// let dayName = Episode.dayName(from: dayOfWeek)
