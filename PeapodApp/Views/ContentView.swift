//
//  ContentView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @EnvironmentObject var appStateManager: AppStateManager
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var toastManager: ToastManager
    @EnvironmentObject var nowPlayingManager: NowPlayingVisibilityManager
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest())
    var subscriptions: FetchedResults<Podcast>
    @StateObject private var episodesViewModel: EpisodesViewModel = EpisodesViewModel.placeholder()
    @State private var showSettings = false
    @State private var lastRefreshDate = Date.distantPast
    @State private var selectedEpisode: Episode? = nil
    
    var namespace: Namespace.ID

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                MainBackground()
                
                ScrollView {
                    QueueView(namespace: namespace)
                    LibraryView(namespace: namespace)
                    SubscriptionsView(namespace: namespace)
                    
                    Spacer().frame(height: 96)
                }
                .maskEdge(.top)
                .maskEdge(.bottom)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // Clear badge when app becomes active
                        UIApplication.shared.applicationIconBadgeNumber = 0
                        
                        // 🚀 NEW: Only refresh if it's been more than 30 seconds since last refresh
                        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshDate)
                        if timeSinceLastRefresh > 30 {
                            print("📱 App foregrounding - refreshing (last refresh: \(String(format: "%.1f", timeSinceLastRefresh))s ago)")
                            forceRefreshPodcasts()
                        } else {
                            print("📱 App foregrounding - skipping refresh (last refresh: \(String(format: "%.1f", timeSinceLastRefresh))s ago)")
                        }
                    }
                }
                .scrollDisabled(subscriptions.isEmpty)
                .refreshable {
                    // Manual pull to refresh - always allow
                    refreshPodcasts(source: "pull-to-refresh")
                }
                
                VStack(alignment: .trailing) {
                    NavigationLink {
                        PPPopover(showBg: true) {
                            SettingsView(namespace: namespace)
                        }
                    } label: {
                        Label("Settings", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(PPButton(type: .transparent, colorStyle: .monochrome, iconOnly: true))
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
            }
            .background(
                EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color.surface, location: 0.00),
                        Gradient.Stop(color: Color.background, location: 1.00),
                    ],
                    center: UnitPoint(x: 0, y: 0)
                )
            )
        }
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
            EpisodeView(episode: episode, namespace:namespace)
                .modifier(PPSheet())
        }
        .overlay {
            if nowPlayingManager.isVisible {
                NowPlaying(namespace: namespace)
            }
        }
        .onAppear {
            UIApplication.shared.applicationIconBadgeNumber = 0
            
            if episodesViewModel.context == nil { // not yet initialized properly
                episodesViewModel.setup(context: context)
            }
            
            // 🚀 NEW: Only refresh on first appear or after significant time gap
            let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshDate)
            if timeSinceLastRefresh > 30 {
                print("📱 ContentView appeared - refreshing (last refresh: \(String(format: "%.1f", timeSinceLastRefresh))s ago)")
                forceRefreshPodcasts()
            } else {
                print("📱 ContentView appeared - skipping refresh (last refresh: \(String(format: "%.1f", timeSinceLastRefresh))s ago)")
            }
            
            checkPendingNotification()
        }
        .onChange(of: appStateManager.currentState) { oldState, newState in
            if oldState != .main && newState == .main {
                // Sync subscriptions when app enters main state
                SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapEpisodeNotification)) { notification in
            if let id = notification.object as? String {
                let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                fetchRequest.fetchLimit = 1
                
                if let foundEpisode = try? context.fetch(fetchRequest).first {
                    print("✅ Opening episode from notification: \(foundEpisode.title ?? "Unknown")")
                    selectedEpisode = foundEpisode
                } else {
                    print("❌ Could not find episode for id \(id)")
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
        
        toastManager.show(message: "Refreshing", icon: "arrow.trianglehead.2.clockwise")
        print("🔄 Force refreshing all subscribed podcasts (\(source))")
        
        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
            toastManager.show(message: "Peapod is up to date", icon: "sparkles")
            print("✨ \(source.capitalized) refreshed feeds at \(Date())")
        }
    }
    
    private func checkPendingNotification() {
        // Check if we have a pending notification episode ID
        if let pendingID = AppDelegate.pendingNotificationEpisodeID {
            print("🔔 Processing pending notification for episode: \(pendingID)")
            // Clear it immediately to prevent duplicate handling
            AppDelegate.pendingNotificationEpisodeID = nil
            
            // Force refresh first to ensure we have the latest episodes
            forceRefreshPodcasts()
            
            // Delay opening the episode to allow refresh to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
            print("❌ Invalid episode ID format: \(episodeID)")
            return
        }
        
        let encodedFeedUrl = components[0]
        let guid = components.dropFirst().joined(separator: "_")
        
        // Decode the feed URL
        guard let feedUrl = encodedFeedUrl.removingPercentEncoding else {
            print("❌ Could not decode feed URL: \(encodedFeedUrl)")
            return
        }
        
        print("🔍 Searching for episode with GUID: \(guid) in feed: \(feedUrl)")
        
        // Find episode by GUID and feed URL
        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "guid == %@ AND podcast.feedUrl == %@", guid, feedUrl)
        fetchRequest.fetchLimit = 1
        
        do {
            if let foundEpisode = try context.fetch(fetchRequest).first {
                print("✅ Found episode from notification: \(foundEpisode.title ?? "Unknown")")
                selectedEpisode = foundEpisode
            } else {
                print("❌ Could not find episode with GUID: \(guid) in feed: \(feedUrl)")
                // Try fallback search by GUID only
                let fallbackRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                fallbackRequest.predicate = NSPredicate(format: "guid == %@", guid)
                fallbackRequest.fetchLimit = 1
                
                if let fallbackEpisode = try context.fetch(fallbackRequest).first {
                    print("✅ Found episode via fallback search: \(fallbackEpisode.title ?? "Unknown")")
                    selectedEpisode = fallbackEpisode
                } else {
                    print("❌ Episode not found even with fallback search")
                }
            }
        } catch {
            print("❌ Error searching for episode: \(error)")
        }
    }
}
