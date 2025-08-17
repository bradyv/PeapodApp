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
            Peapod
                .transition(.opacity)
        }
    }
    
    @ViewBuilder
    var Peapod: some View {
        TabView(selection: $selectedTab) {
            Tab("Listen", systemImage: "play.square.stack", value: .listen) {
                NavigationStack {
                    ZStack {
                        MainBackground()
                        
                        ScrollView {
                            QueueView(selectedTab: $selectedTab)
                            LatestEpisodesView(mini: true, maxItems: 3)
                        }
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
            
            Tab("Library", systemImage: "circle.grid.3x3", value: .library) {
                NavigationStack {
                    ScrollView {
                        SubscriptionsView()
                        FavEpisodesView(mini: true, maxItems: 3)
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
            
            Tab("Search", systemImage: "plus.magnifyingglass", value: .search, role: .search) {
                NavigationStack {
                    PodcastSearchView(searchQuery: $query)
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
            NowPlayingBar
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
        .onAppear {
            checkPendingNotification()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Clear badge when app becomes active
                UNUserNotificationCenter.current().setBadgeCount(0)
                
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
    
    @ViewBuilder
    var NowPlayingBar: some View {
        Group {
            if let episode = firstQueueEpisode {
                let artwork = episode.episodeImage ?? episode.podcast?.image ?? ""
                HStack {
                    HStack {
                        ArtworkView(url: artwork, size: 36, cornerRadius: 18, tilt: false)
                        
                        VStack(alignment:.leading) {
                            Text(episode.podcast?.title ?? "Podcast title")
                                .textDetail()
                                .lineLimit(1)
                            
                            Text(episode.title ?? "Episode title")
                                .textBody()
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEpisode = episode
                    }
                    
                    HStack {
                        Button(action: {
                            player.togglePlayback(for: episode)
                            print("Playing episode")
                        }) {
                            if player.isLoading {
                                PPSpinner(color: Color.heading)
                            } else if player.isPlaying {
                                Image(systemName: "pause")
                            } else {
                                Image(systemName: "play.fill")
                            }
                        }
                        
                        Button(action: {
                            player.skipForward(seconds: player.forwardInterval)
                            print("Seeking forward")
                        }) {
                            Label("Go forward", systemImage: "\(String(format: "%.0f", player.forwardInterval)).arrow.trianglehead.clockwise")
                        }
                        .disabled(!player.isPlaying)
                    }
                }
                .padding(.leading,4)
                .padding(.trailing, 8)
                .frame(maxWidth:.infinity, alignment:.leading)
            } else {
                HStack {
                    Text("Nothing playing")
                        .textBody()
                        .frame(maxWidth:.infinity, alignment: .leading)

                    HStack {
                        Button(action: {
                        }) {
                            Image(systemName: "play.fill")
                        }
                        .disabled(player.isPlaying)
                        
                        Button(action: {
                        }) {
                            Label("Go forward", systemImage: "\(String(format: "%.0f", player.forwardInterval)).arrow.trianglehead.clockwise")
                        }
                        .disabled(!player.isPlaying)
                    }
                }
                .padding(.leading,16).padding(.trailing, 8)
                .frame(maxWidth:.infinity, alignment:.leading)
            }
        }
        .id(episodeID)
        .onChange(of: firstQueueEpisode?.id) { _ in
            episodeID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            // Refresh queue when Core Data changes
            loadQueue()
        }
        .onAppear {
            loadQueue()
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
    
//    func debugSyncAfterReinstall() {
//        let context = PersistenceController.shared.container.viewContext
//        
//        print("\n🔍 DEBUGGING SYNC AFTER REINSTALL:")
//        print("=====================================")
//        
//        // Check what playlists exist
//        let playlistRequest: NSFetchRequest<Playlist> = Playlist.fetchRequest()
//        let playlists = (try? context.fetch(playlistRequest)) ?? []
//        print("📝 Playlists found: \(playlists.count)")
//        for playlist in playlists {
//            let name = playlist.name ?? "Unknown"
//            let episodeCount = playlist.episodeIdArray.count
//            print("   - \(name): \(episodeCount) episodes")
//            
//            // Show first few episode IDs
//            let episodeIds = playlist.episodeIdArray
//            if !episodeIds.isEmpty {
//                print("     Episode IDs: \(Array(episodeIds.prefix(3)))")
//            }
//        }
//        
//        // Check what playback states exist
//        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
//        let playbacks = (try? context.fetch(playbackRequest)) ?? []
//        print("\n▶️ Playback states found: \(playbacks.count)")
//        for playback in playbacks {
//            let episodeId = playback.episodeId ?? "Unknown"
//            let position = playback.playbackPosition
//            let playCount = playback.playCount
//            let queuePos = playback.queuePosition
//            print("   - Episode: \(episodeId)")
//            print("     Position: \(position)s, PlayCount: \(playCount), Queue: \(queuePos)")
//        }
//        
//        // Check specific playlists
//        print("\n📋 Checking specific playlists:")
//        let queuePlaylist = getPlaylist(named: "Queue", context: context)
//        let favPlaylist = getPlaylist(named: "Favorites", context: context)
//        let playedPlaylist = getPlaylist(named: "Played", context: context)
//        
//        print("   Queue: \(queuePlaylist.episodeIdArray.count) episodes")
//        print("   Favorites: \(favPlaylist.episodeIdArray.count) episodes")
//        print("   Played: \(playedPlaylist.episodeIdArray.count) episodes")
//        
//        // Check if episodes exist locally
//        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
//        let episodes = (try? context.fetch(episodeRequest)) ?? []
//        print("\n📺 Episodes in local store: \(episodes.count)")
//        
//        print("=====================================\n")
//    }
    
//    func debugEpisodeIDs() {
//        let context = PersistenceController.shared.container.viewContext
//        
//        // Get a few episodes and their IDs
//        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
//        episodeRequest.fetchLimit = 5
//        let episodes = (try? context.fetch(episodeRequest)) ?? []
//        
//        print("🆔 Current Episode IDs:")
//        for episode in episodes {
//            print("   \(episode.title ?? "Unknown"): \(episode.id ?? "No ID")")
//        }
//        
//        // Check what's in queue playlist
//        let queuePlaylist = getPlaylist(named: "Queue", context: context)
//        print("📋 Queue Playlist Episode IDs:")
//        for id in queuePlaylist.episodeIdArray.prefix(5) {
//            print("   \(id)")
//        }
//    }

}
