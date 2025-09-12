//
//  ContentView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appStateManager: AppStateManager
    @EnvironmentObject var toastManager: ToastManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.scenePhase) private var scenePhase
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest())
    var subscriptions: FetchedResults<Podcast>
    @State private var lastRefreshDate = Date.distantPast
    @State private var selectedEpisode: Episode? = nil
    @State private var query = ""
    @State private var selectedTab: Tabs = .listen
    @State private var queue: [Episode] = []
    @State private var episodeID = UUID()
    @State private var rotateTrigger = false
    @State private var selectedEpisodeForNavigation: Episode? = nil
    @Namespace private var namespace
    
    private var firstQueueEpisode: Episode? {
        queue.first
    }
    
    enum Tabs: Hashable {
        case listen
        case library
        case search
    }

    var body: some View {
        switch appStateManager.currentState {
        case .onboarding:
            WelcomeView(
                completeOnboarding: {
                    appStateManager.completeOnboarding()
                }
            )
            .transition(.opacity)
            
        case .main:
            HomeView
                .transition(.opacity)
                .onAppear {
                    checkPendingNotification()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // Clear badge when app becomes active
                        UNUserNotificationCenter.current().setBadgeCount(0)
                        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                        
                        // 🚀 NEW: Only refresh if it's been more than 30 seconds since last refresh
                        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshDate)
                        if timeSinceLastRefresh > 30 {
                            LogManager.shared.info("📱 App foregrounding - refreshing (last refresh: \(String(format: "%.1f", timeSinceLastRefresh))s ago)")
                            forceRefreshPodcasts()
                        } else {
                            LogManager.shared.info("📱 App foregrounding - skipping refresh (last refresh: \(String(format: "%.1f", timeSinceLastRefresh))s ago)")
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .didTapEpisodeNotification)) { notification in
                    if let id = notification.object as? String {
                        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                        fetchRequest.fetchLimit = 1
                        
                        if let foundEpisode = try? context.fetch(fetchRequest).first {
                            LogManager.shared.info("✅ Opening episode from notification: \(foundEpisode.title ?? "Unknown")")
                            selectedEpisode = foundEpisode
                        } else {
                            LogManager.shared.error("❌ Could not find episode for id \(id)")
                        }
                    }
                }
                .toast()
        }
    }
    
    @ViewBuilder
    var HomeView: some View {
        NavigationStack {
            ZStack {
                MainBackground()
                
                ScrollView {
                    VStack(spacing: 32) {
                        QueueView(selectedTab: $selectedTab)
                        LatestEpisodesView(mini:true, maxItems: 5)
                        FavEpisodesView(mini: true, maxItems: 5)
                        SubscriptionsRow()
                    }
                    .scrollClipDisabled(true)
                }
                
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        PodcastSearchView(searchQuery: $query)
                            .searchable(text: $query, prompt: "Find a Podcast")
                            .navigationTitle("Find a Podcast")
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "person.crop.circle")
                    }
                    .labelStyle(.iconOnly)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    NowPlayingBar(selectedEpisodeForNavigation: $selectedEpisodeForNavigation)
                }
            }
            .navigationDestination(item: $selectedEpisodeForNavigation) { episode in
                EpisodeView(episode: episode)
                    .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
            }
        }
    }
    
    private func loadQueue() {
        queue = fetchEpisodesInPlaylist(named: "Queue", context: context)
    }
    
    // 🚀 UPDATED: Unified refresh method with source tracking and debouncing
    private func forceRefreshPodcasts() {
        refreshPodcasts(source: "auto")
    }
    
    private func refreshPodcasts(source: String) {
        // Update last refresh time immediately to prevent concurrent calls
        lastRefreshDate = Date()
        
        if source != "auto" {
            toastManager.show(message: "Refreshing", icon: "arrow.trianglehead.2.clockwise")
        }
        LogManager.shared.info("🔄 Force refreshing all subscribed podcasts (\(source))")
        
        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
            if source != "auto" {
                toastManager.show(message: "Peapod is up to date", icon: "sparkles")
            }
            LogManager.shared.info("✨ \(source.capitalized) refreshed feeds")
        }
    }
    
    private func checkPendingNotification() {
        // Check if we have a pending notification episode ID
        if let pendingID = AppDelegate.pendingNotificationEpisodeID {
            LogManager.shared.info("🔔 Processing pending notification for episode: \(pendingID)")
            // Clear it immediately to prevent duplicate handling
            AppDelegate.pendingNotificationEpisodeID = nil
            
            // Force refresh first to ensure we have the latest episodes
            forceRefreshPodcasts()
            
            // Delay opening the episode to allow refresh to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                // Try to find the episode by the Firebase episode ID format
                self.findEpisodeByFirebaseId(pendingID)
            }
        }
    }
    
    // 🆕 Helper to find episode using Firebase episode ID format
    private func findEpisodeByFirebaseId(_ episodeID: String) {
        // Firebase episode IDs are in format: encodedFeedUrl_guid
        let components = episodeID.components(separatedBy: "_")
        guard components.count >= 2 else {
            LogManager.shared.error("❌ Invalid episode ID format: \(episodeID)")
            return
        }
        
        let encodedFeedUrl = components[0]
        let guid = components.dropFirst().joined(separator: "_")
        
        // Decode the feed URL
        guard let feedUrl = encodedFeedUrl.removingPercentEncoding else {
            LogManager.shared.error("❌ Could not decode feed URL: \(encodedFeedUrl)")
            return
        }
        
        print("🔍 Searching for episode with GUID: \(guid) in feed: \(feedUrl)")
        
        // Find episode by GUID and feed URL
        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "guid == %@ AND podcast.feedUrl == %@", guid, feedUrl)
        fetchRequest.fetchLimit = 1
        
        do {
            if let foundEpisode = try context.fetch(fetchRequest).first {
                LogManager.shared.info("✅ Found episode from notification: \(foundEpisode.title ?? "Unknown")")
                selectedEpisode = foundEpisode
            } else {
                LogManager.shared.error("❌ Could not find episode with GUID: \(guid) in feed: \(feedUrl)")
                // Try fallback search by GUID only
                let fallbackRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                fallbackRequest.predicate = NSPredicate(format: "guid == %@", guid)
                fallbackRequest.fetchLimit = 1
                
                if let fallbackEpisode = try context.fetch(fallbackRequest).first {
                    LogManager.shared.info("✅ Found episode via fallback search: \(fallbackEpisode.title ?? "Unknown")")
                    selectedEpisode = fallbackEpisode
                } else {
                    LogManager.shared.error("❌ Episode not found even with fallback search")
                }
            }
        } catch {
            LogManager.shared.error("❌ Error searching for episode: \(error)")
        }
    }

}
