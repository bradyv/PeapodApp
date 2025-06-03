//
//  FetchRequests.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-28.
//

import SwiftUI
import CoreData

extension Episode {
    static func queueFetchRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "playlist.name == %@", "Queue")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.queuePosition, ascending: true)]
        request.fetchBatchSize = 20
        return request
    }
    
    static func latestEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcast != nil AND podcast.isSubscribed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchBatchSize = 20
        return request
    }
    
    static func unplayedEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcast != nil AND podcast.isSubscribed == YES AND isPlayed == NO AND playbackPosition == 0 AND nowPlaying = NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchBatchSize = 20
        return request
    }
    
    static func savedEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "isSaved == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.savedDate, ascending: false)]
        request.fetchBatchSize = 20
        return request
    }
    
    static func favEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "isFav == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.favDate, ascending: false)]
        request.fetchBatchSize = 20
        return request
    }
    
    static func oldEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "(podcast = nil OR podcast.isSubscribed != YES) AND isSaved == NO AND isPlayed == NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.id, ascending: true)]
        request.fetchBatchSize = 20
        return request
    }
    
    // Moved from ActivityView.swift
    static func recentlyPlayedRequest(limit: Int = 5) -> NSFetchRequest<Episode> {
        let request = NSFetchRequest<Episode>(entityName: "Episode")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.playedDate, ascending: false)]
        request.predicate = NSPredicate(format: "isPlayed == YES")
        request.fetchLimit = limit
        return request
    }
    
    // NEW: Get the longest played episode
    static func longestPlayedEpisodeRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "isPlayed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.actualDuration, ascending: false)]
        request.fetchLimit = 1
        return request
    }
    
    // NEW: Get played episodes grouped by day of week (for analysis)
    static func playedEpisodesByDayRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "isPlayed == YES AND playedDate != nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.playedDate, ascending: true)]
        return request
    }
    
    // NEW: Helper function to get most popular listening day
    static func mostPopularListeningDay(in context: NSManagedObjectContext) throws -> (dayOfWeek: Int, count: Int)? {
        let request = Episode.playedEpisodesByDayRequest()
        let episodes = try context.fetch(request)
        
        var dayCount: [Int: Int] = [:]
        let calendar = Calendar.current
        
        for episode in episodes {
            guard let playedDate = episode.playedDate else { continue }
            let dayOfWeek = calendar.component(.weekday, from: playedDate)
            dayCount[dayOfWeek, default: 0] += 1
        }
        
        guard let maxDay = dayCount.max(by: { $0.value < $1.value }) else {
            return nil
        }
        
        return (dayOfWeek: maxDay.key, count: maxDay.value)
    }
    
    static func getWeeklyListeningData(in context: NSManagedObjectContext) throws -> [WeeklyListeningData] {
        let request = Episode.playedEpisodesByDayRequest()
        let episodes = try context.fetch(request)
        
        var dayCount: [Int: Int] = [:]
        let calendar = Calendar.current
        
        // Count episodes for each day of the week
        for episode in episodes {
            guard let playedDate = episode.playedDate else { continue }
            let dayOfWeek = calendar.component(.weekday, from: playedDate)
            dayCount[dayOfWeek, default: 0] += 1
        }
        
        // Find the maximum count for percentage calculation
        let maxCount = dayCount.values.max() ?? 1
        
        // Create data for all 7 days (1 = Sunday, 7 = Saturday)
        let dayAbbreviations = ["S", "M", "T", "W", "T", "F", "S"] // Sun, Mon, Tue, Wed, Thu, Fri, Sat
        
        var weeklyData: [WeeklyListeningData] = []
        
        for day in 1...7 {
            let count = dayCount[day] ?? 0
            let percentage = maxCount > 0 ? Double(count) / Double(maxCount) : 0.0
            
            weeklyData.append(WeeklyListeningData(
                dayOfWeek: day,
                count: count,
                percentage: percentage,
                dayAbbreviation: dayAbbreviations[day - 1]
            ))
        }
        
        return weeklyData
    }

    
    // NEW: Helper function to get day name from weekday number
    static func dayName(from weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let dayNames = formatter.weekdaySymbols!
        // weekday is 1-based (1 = Sunday), array is 0-based
        return dayNames[weekday - 1]
    }
    
    // NEW: Count total episodes in database
    static func totalEpisodeCount(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<Episode>(entityName: "Episode")
        request.resultType = .countResultType
        return try context.count(for: request)
    }
    
    // NEW: Repeat listens
    static func topPlayedEpisodesRequest(limit: Int = 3) -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "playCount > 1")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.playCount, ascending: false)]
        request.fetchLimit = limit
        return request
    }
}

extension Podcast {
    static func subscriptionsFetchRequest() -> NSFetchRequest<Podcast> {
        let request = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Podcast.title, ascending: true)]
        request.fetchBatchSize = 20
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

        if rounded < 0.1 {
            return "Under 1 hour"
        }

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

// MARK: - App Statistics Helper

struct AppStatistics {
    let podcastCount: Int
    let episodeCount: Int
    let totalPlayedSeconds: Double
    let subscribedCount: Int
    let playCount: Int
    
    static func load(from context: NSManagedObjectContext) async throws -> AppStatistics {
        let podcasts = try Podcast.totalPodcastCount(in: context)
        let episodes = try Episode.totalEpisodeCount(in: context)
        let playedSeconds = try await Podcast.totalPlayedDuration(in: context)
        let subscribed = try Podcast.totalSubscribedCount(in: context)
        let plays = try Podcast.totalPlayCount(in: context)
        
        return AppStatistics(
            podcastCount: podcasts,
            episodeCount: episodes,
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
