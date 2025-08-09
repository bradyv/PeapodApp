//
//  ContentView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var toastManager: ToastManager
    @EnvironmentObject var nowPlayingManager: NowPlayingVisibilityManager
    @Environment(\.scenePhase) private var scenePhase
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest())
    var subscriptions: FetchedResults<Podcast>
    @StateObject private var episodesViewModel: EpisodesViewModel = EpisodesViewModel.placeholder()
    @State private var showSettings = false
    @State private var lastRefreshDate = Date.distantPast
    @State private var selectedEpisode: Episode? = nil
    @State private var query = ""

    var body: some View {
        TabView {
            Tab("Listen", systemImage: "play.square.stack") {
                NavigationStack {
                    ZStack {
                        MainBackground()
                        
                        ScrollView {
                            QueueView()
                            LatestEpisodesMini()
                        }
                        .background(Color.clear)
                    }
                    .background(Color.background)
                    .scrollEdgeEffectStyle(.soft, for: .all)
                    .navigationTitle("Listen")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Label("Settings", systemImage: "person.crop.circle")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            
            Tab("Library", systemImage: "circle.grid.3x3") {
                NavigationStack {
                    ScrollView {
                        SubscriptionsView()
                        FavEpisodesMini()
                    }
                    .background(Color.background)
                    .scrollEdgeEffectStyle(.soft, for: .all)
                    .navigationTitle("Library")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            NavigationLink {
                               SettingsView()
                           } label: {
                               Label("Settings", systemImage: "person.crop.circle")
                           }
                           .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            
            Tab("Search", systemImage: "plus.magnifyingglass", role: .search) {
                NavigationStack {
                    PodcastSearchView(searchQuery: $query)
                        .background(Color.background)
                        .searchable(text: $query, prompt: "Find a Podcast")
                        .navigationTitle("Find a Podcast")
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                NavigationLink {
                                   SettingsView()
                               } label: {
                                   Label("Settings", systemImage: "person.crop.circle")
                               }
                               .labelStyle(.iconOnly)
                            }
                        }
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
            }
        }
        .tabViewBottomAccessory {
            NowPlaying()
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environmentObject(episodesViewModel)
        // Track subscription changes for backend sync
        .onChange(of: subscriptions.count) { oldCount, newCount in
            if oldCount != newCount {
                // Delay sync to allow Core Data to settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
                }
            }
        }
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
        .onAppear {
            if episodesViewModel.context == nil { // not yet initialized properly
                episodesViewModel.setup(context: context)
            }
            
            checkPendingNotification()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Clear badge when app becomes active
                UIApplication.shared.applicationIconBadgeNumber = 0
                
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
