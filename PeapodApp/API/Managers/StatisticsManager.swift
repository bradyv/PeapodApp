//
//  StatisticsManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-10-04.
//

import SwiftUI
import CoreData
import Combine

class StatisticsManager: ObservableObject {
    static let shared = StatisticsManager()
    
    @Published var podcastCount: Int = 0
    @Published var totalPlayedSeconds: Double = 0
    @Published var subscribedCount: Int = 0
    @Published var playCount: Int = 0
    @Published var weeklyData: [WeeklyListeningData] = []
    @Published var favoriteDayName: String = "Loading..."
    @Published var favoriteDayCount: Int = 0
    
    private var cancellables = Set<AnyCancellable>()
    private var hasInitialLoad = false
    private var isLoading = false
    
    private init() {
        // Stats will be loaded when context is first set
    }
    
    // Call this once when your app starts with the main context
    func initialize(with context: NSManagedObjectContext) {
        guard !hasInitialLoad else { return }
        hasInitialLoad = true
        
        // Initial load
        Task {
            await refreshStats(from: context, animated: false)
        }
        
        // Setup automatic updates on Core Data changes
        setupObservers(context: context)
    }
    
    // Private refresh that does the actual work
    private func refreshStats(from context: NSManagedObjectContext, animated: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        
        do {
            // Perform all Core Data work on background context
            let bgContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            bgContext.parent = context
            
            // Load basic stats
            let podcasts = try await bgContext.perform {
                try Podcast.totalPodcastCount(in: bgContext)
            }
            
            let playedSeconds = try await Podcast.totalPlayedDuration(in: bgContext)
            
            let subscribed = try await bgContext.perform {
                try Podcast.totalSubscribedCount(in: bgContext)
            }
            
            let plays = try await bgContext.perform {
                try Podcast.totalPlayCount(in: bgContext)
            }
            
            // Load weekly data
            let weeklyListeningData = await bgContext.perform {
                self.getWeeklyListeningData(context: bgContext)
            }
            
            let favoriteDay = await bgContext.perform {
                self.getMostPopularListeningDay(context: bgContext)
            }
            
            // Update on main thread
            await MainActor.run {
                // No animation by default - animations during navigation cause lag
                if animated {
                    withAnimation(.easeInOut) {
                        self.updateProperties(
                            podcasts: podcasts,
                            playedSeconds: playedSeconds,
                            subscribed: subscribed,
                            plays: plays,
                            weeklyData: weeklyListeningData,
                            favoriteDay: favoriteDay
                        )
                    }
                } else {
                    self.updateProperties(
                        podcasts: podcasts,
                        playedSeconds: playedSeconds,
                        subscribed: subscribed,
                        plays: plays,
                        weeklyData: weeklyListeningData,
                        favoriteDay: favoriteDay
                    )
                }
                self.isLoading = false
            }
        } catch {
            LogManager.shared.error("Error loading statistics: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func updateProperties(
        podcasts: Int,
        playedSeconds: Double,
        subscribed: Int,
        plays: Int,
        weeklyData: [WeeklyListeningData],
        favoriteDay: (Int, Int)?
    ) {
        self.podcastCount = podcasts
        self.totalPlayedSeconds = playedSeconds
        self.subscribedCount = subscribed
        self.playCount = plays
        self.weeklyData = weeklyData
        
        if let (dayOfWeek, count) = favoriteDay {
            self.favoriteDayName = self.dayName(from: dayOfWeek)
            self.favoriteDayCount = count
        } else {
            self.favoriteDayName = "No data yet"
            self.favoriteDayCount = 0
        }
    }
    
    // Public method to manually refresh if needed (e.g., after bulk import)
    func refresh(context: NSManagedObjectContext) {
        Task {
            await refreshStats(from: context, animated: true)
        }
    }
    
    // Computed properties for convenience
    var totalPlayedHours: Int {
        Int(totalPlayedSeconds) / 3600
    }
    
    var formattedPlayedHours: String {
        let hours = totalPlayedHours
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
    
    var formattedPlayCount: String {
        playCount == 1 ? "1 episode" : "\(playCount) episodes"
    }
    
    // MARK: - Weekly Data Helpers
    
    private func getWeeklyListeningData(context: NSManagedObjectContext) -> [WeeklyListeningData] {
        let playedEpisodes = getPlayedEpisodes(context: context)
        var dayCounts: [Int: Int] = [:]
        let calendar = Calendar.current
        
        for episode in playedEpisodes {
            if let playedDate = episode.playedDate {
                let dayOfWeek = calendar.component(.weekday, from: playedDate)
                dayCounts[dayOfWeek, default: 0] += 1
            }
        }
        
        let maxCount = dayCounts.values.max() ?? 1
        
        return (1...7).map { dayOfWeek in
            let count = dayCounts[dayOfWeek] ?? 0
            let percentage = maxCount > 0 ? Double(count) / Double(maxCount) : 0.0
            let dayAbbreviation = dayAbbreviation(from: dayOfWeek)
            
            return WeeklyListeningData(
                dayOfWeek: dayOfWeek,
                count: count,
                percentage: percentage,
                dayAbbreviation: dayAbbreviation
            )
        }
    }
    
    private func getMostPopularListeningDay(context: NSManagedObjectContext) -> (Int, Int)? {
        let playedEpisodes = getPlayedEpisodes(context: context)
        var dayCounts: [Int: Int] = [:]
        let calendar = Calendar.current
        
        for episode in playedEpisodes {
            if let playedDate = episode.playedDate {
                let dayOfWeek = calendar.component(.weekday, from: playedDate)
                dayCounts[dayOfWeek, default: 0] += 1
            }
        }
        
        return dayCounts.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
    
    private func dayName(from dayOfWeek: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let date = Calendar.current.date(from: DateComponents(weekday: dayOfWeek))!
        return formatter.string(from: date)
    }
    
    private func dayAbbreviation(from dayOfWeek: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        let date = Calendar.current.date(from: DateComponents(weekday: dayOfWeek))!
        return String(formatter.string(from: date).prefix(1))
    }
    
    // MARK: - Observer Setup
    
    private func setupObservers(context: NSManagedObjectContext) {
        // Auto-refresh when Core Data changes (debounced to avoid excessive updates)
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let notificationContext = notification.object as? NSManagedObjectContext else { return }
                // Only refresh if the notification is from our context or a child context
                if notificationContext == context || notificationContext.parent == context {
                    self?.refresh(context: context)
                }
            }
            .store(in: &cancellables)
    }
}
