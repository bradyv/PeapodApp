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
    @StateObject private var episodeSelectionManager = EpisodeSelectionManager()
    @State private var showSettings = false
    @State private var currentEpisodeID: String? = nil
    @State private var lastRefreshDate = Date.distantPast
    var namespace: Namespace.ID

    var body: some View {
        NavigationStack {
            ZStack(alignment:.topTrailing) {
                NowPlayingSplash(episodeID: currentEpisodeID)
                    .matchedGeometryEffect(id: "page-bg", in: namespace)
                
                ScrollView {
                    FadeInView(delay: 0.1) {
                        QueueView(currentEpisodeID: $currentEpisodeID, namespace: namespace)
                    }
                    FadeInView(delay: 0.2) {
                        LibraryView(namespace: namespace)
                    }
                    FadeInView(delay: 0.3) {
                        SubscriptionsView(namespace: namespace)
                    }
                    
                    Spacer().frame(height:96)
                }
                .maskEdge(.top)
                .maskEdge(.bottom)
                .onAppear {
                    // Clear badge when app appears
                    UIApplication.shared.applicationIconBadgeNumber = 0
                    
                    // Force refresh to get latest episodes
                    let now = Date()
                    if now.timeIntervalSince(lastRefreshDate) > 300 { // only refresh if >5min since last refresh
                        lastRefreshDate = now
                        forceRefreshPodcasts()
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // Clear badge when app becomes active
                        UIApplication.shared.applicationIconBadgeNumber = 0
                        
                        // Force refresh when app becomes active to get new episodes
                        let now = Date()
                        if now.timeIntervalSince(lastRefreshDate) > 300 { // only refresh if >5min since last refresh
                            lastRefreshDate = now
                            forceRefreshPodcasts()
                        }
                    }
                }
                .scrollDisabled(subscriptions.isEmpty)
                .refreshable {
                    // Manual pull to refresh - full refresh
                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                        toastManager.show(message: "Updated All Feeds", icon: "sparkles")
                    }
                }
                
                VStack(alignment:.trailing) {
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
                .frame(maxWidth:.infinity, alignment:.trailing)
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
        .environmentObject(episodeSelectionManager)
        // Track subscription changes for backend sync
        .onChange(of: subscriptions.count) { oldCount, newCount in
            if oldCount != newCount {
                // Delay sync to allow Core Data to settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
                }
            }
        }
        .overlay {
            if nowPlayingManager.isVisible {
                NowPlaying(namespace: namespace) { episode in
                    episodeSelectionManager.selectEpisode(episode)
                }
                .environmentObject(episodeSelectionManager)
            }
        }
        .sheet(item: $episodeSelectionManager.selectedEpisode) { episode in
            EpisodeView(episode: episode, namespace: namespace)
                .modifier(PPSheet())
        }
        .onAppear {
            if episodesViewModel.context == nil { // not yet initialized properly
                episodesViewModel.setup(context: context)
            }
            
            checkPendingNotification()
        }
        .onChange(of: appStateManager.currentState) { oldState, newState in
            if oldState != .main && newState == .main {
                // Sync subscriptions when app enters main state
                SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
                
                // Also force refresh to get latest episodes
                forceRefreshPodcasts()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapEpisodeNotification)) { notification in
            if let id = notification.object as? String {
                let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                fetchRequest.fetchLimit = 1
                
                if let foundEpisode = try? context.fetch(fetchRequest).first {
                    print("✅ Opening episode from notification: \(foundEpisode.title ?? "Unknown")")
                    episodeSelectionManager.selectEpisode(foundEpisode)
                } else {
                    print("❌ Could not find episode for id \(id)")
                }
            }
        }
        .toast()
    }
    
    // 🆕 Force refresh to actually fetch new episodes (not just light refresh)
    private func forceRefreshPodcasts() {
        print("🔄 Force refreshing all subscribed podcasts")
        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
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
                episodeSelectionManager.selectEpisode(foundEpisode)
            } else {
                print("❌ Could not find episode with GUID: \(guid) in feed: \(feedUrl)")
                // Try fallback search by GUID only
                let fallbackRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                fallbackRequest.predicate = NSPredicate(format: "guid == %@", guid)
                fallbackRequest.fetchLimit = 1
                
                if let fallbackEpisode = try context.fetch(fallbackRequest).first {
                    print("✅ Found episode via fallback search: \(fallbackEpisode.title ?? "Unknown")")
                    episodeSelectionManager.selectEpisode(fallbackEpisode)
                } else {
                    print("❌ Episode not found even with fallback search")
                }
            }
        } catch {
            print("❌ Error searching for episode: \(error)")
        }
    }
}
