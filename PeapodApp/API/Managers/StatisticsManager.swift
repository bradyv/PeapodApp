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
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Subscribe to data changes if needed
        setupObservers()
    }
    
    // Load statistics from context
    func loadStatistics(from context: NSManagedObjectContext) async {
        do {
            let podcasts = try Podcast.totalPodcastCount(in: context)
            let playedSeconds = try await Podcast.totalPlayedDuration(in: context)
            let subscribed = try Podcast.totalSubscribedCount(in: context)
            let plays = try Podcast.totalPlayCount(in: context)
            
            await MainActor.run {
                withAnimation(.easeInOut) {
                    self.podcastCount = podcasts
                    self.totalPlayedSeconds = playedSeconds
                    self.subscribedCount = subscribed
                    self.playCount = plays
                }
            }
        } catch {
            LogManager.shared.error("Error loading statistics: \(error)")
        }
    }
    
    // Refresh statistics (call this after major data changes)
    func refresh(context: NSManagedObjectContext) {
        Task {
            await loadStatistics(from: context)
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
    
    // Setup observers for Core Data changes if you want automatic updates
    private func setupObservers() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let context = notification.object as? NSManagedObjectContext else { return }
                self?.refresh(context: context)
            }
            .store(in: &cancellables)
    }
}
