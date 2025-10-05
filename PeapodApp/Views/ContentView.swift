//
//  ContentView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

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
    @State private var episodeID = UUID()
    @State private var rotateTrigger = false
    @State private var selectedEpisodeForNavigation: Episode? = nil
    @StateObject private var opmlImportManager = OPMLImportManager()
    @State private var showFileBrowser: Bool = false
    @State private var selectedOPMLContent: String = ""
    @Namespace private var namespace
    
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
                .fileImporter(
                    isPresented: $showFileBrowser,
                    allowedContentTypes: [
                        .xml,
                        .plainText,
                        UTType(filenameExtension: "opml") ?? .xml,
                        UTType(mimeType: "text/x-opml") ?? .xml
                    ],
                    allowsMultipleSelection: false
                ) { result in
                    do {
                        guard let selectedFile: URL = try result.get().first else { return }
                        
                        // Start accessing the security-scoped resource
                        guard selectedFile.startAccessingSecurityScopedResource() else {
                            LogManager.shared.error("Couldn't access security-scoped resource")
                            return
                        }
                        
                        defer {
                            selectedFile.stopAccessingSecurityScopedResource()
                        }
                        
                        // Now read the file
                        let xmlContent = try String(contentsOf: selectedFile, encoding: .utf8)
                        selectedOPMLContent = xmlContent
                        
                        // Start the import process
                        opmlImportManager.importOPML(xmlString: xmlContent, context: context)
                    } catch {
                        LogManager.shared.error("Unable to read OPML file: \(error.localizedDescription)")
                    }
                }
                .alert("Import Complete", isPresented: $opmlImportManager.isComplete, actions: {
                    // Leave empty to use the default "OK" action.
                }, message: {
                    Text("Subscribed to \(opmlImportManager.processedPodcasts) of \(opmlImportManager.totalPodcasts) podcasts.")
                })
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
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PlayEpisodeFromCarPlay"))) { notification in
                    print("🎵 ContentView received CarPlay play notification")
                    if let episodeID = notification.object as? String {
                        print("🎵 Looking for episode with ID: \(episodeID)")
                        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", episodeID)
                        fetchRequest.fetchLimit = 1
                        
                        if let episode = try? context.fetch(fetchRequest).first {
                            print("🎵 Found episode: \(episode.title ?? "Unknown")")
                            print("🎵 Calling togglePlayback")
                            player.togglePlayback(for: episode)
                        } else {
                            print("❌ Episode not found with ID: \(episodeID)")
                        }
                    } else {
                        print("❌ No episode ID in notification")
                    }
                }
//                .toast()
        }
    }
    
    @ViewBuilder
    var EmptyHomeView: some View {
        let window = UIScreen.main.bounds.width - 32
        ZStack {
            ScrollView {
                VStack(alignment:.leading) {
                    SkeletonItem(width:window, height:200, cornerRadius:32)
                        .mask(
                            LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                           startPoint: .top, endPoint: .bottom)
                        )
                    
                    SkeletonItem(width:96, height:24)
                    
                    HStack {
                        ForEach(1...3, id: \.self) {_ in
                            SkeletonItem(width:window / 3, height:window / 3, cornerRadius: 16)
                        }
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    
                    Spacer().frame(height:32)
                    
                    SkeletonItem(width:96, height:24)
                    
                    HStack {
                        SkeletonItem(width:window / 3, height:window / 3, cornerRadius:16)
                        
                        VStack(alignment:.leading) {
                            SkeletonItem(width:96, height:12, cornerRadius:3)
                            
                            SkeletonItem(width:200, height:24)
                            
                            SkeletonItem(width:96, height:40, cornerRadius:20)
                        }
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    
                    Spacer().frame(height:32)
                    
                    SkeletonItem(width:96, height:24)
                    
                    HStack {
                        SkeletonItem(width:window / 3, height:window / 3, cornerRadius:16)
                        
                        VStack(alignment:.leading) {
                            SkeletonItem(width:96, height:12, cornerRadius:3)
                            
                            SkeletonItem(width:200, height:24)
                            
                            SkeletonItem(width:96, height:40, cornerRadius:20)
                        }
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                }
                .frame(maxWidth:.infinity,alignment:.leading)
                .mask(
                    LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0)]),
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .disabled(subscriptions.isEmpty)
            
            VStack(spacing:32) {
                VStack {
                    Text("Your library is empty")
                        .titleCondensed()
                    
                    Text("Follow some podcasts to get started.")
                        .textBody()
                }
                
                VStack(spacing:16) {
                    NavigationLink {
                        PodcastSearchView()
                        
                    } label: {
                        Label("Find a Podcast", systemImage: "plus.magnifyingglass")
                            .padding(.vertical,4)
                            .foregroundStyle(.white)
                            .textBodyEmphasis()
                    }
                    .buttonStyle(.glassProminent)
                    
                    Button {
                        showFileBrowser = true
                    } label: {
                        Label("Import OPML", systemImage: "tray.and.arrow.down")
                            .padding(.vertical,4)
                            .foregroundStyle(Color.accentColor)
                            .textBodyEmphasis()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    var HomeView: some View {
        NavigationStack {
            ZStack {
                if subscriptions.isEmpty {
                    EmptyHomeView
                } else {
                    MainBackground()
                    
                    ScrollView {
                        if episodesViewModel.isLoading {
                            LoadingView
                                .transition(.opacity)
                        } else {
                            VStack(spacing: 32) {
                                QueueView()
                                LatestEpisodesView(mini:true, maxItems: 5)
                                FavEpisodesView(mini: true, maxItems: 5)
                                SubscriptionsRow()
                                Spacer().frame(height:0)
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: episodesViewModel.isLoading)
                }
            }
            .navigationTitle("Up Next")
            .background(Color.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        PodcastSearchView()
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
                
                if !episodesViewModel.queue.isEmpty && !episodesViewModel.isLoading {
                    ToolbarItemGroup(placement: .bottomBar) {
                        MiniPlayer()
                        Spacer()
                        MiniPlayerButton()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var LoadingView: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(spacing:0) {
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        HStack(spacing: 16) {
                            EmptyQueueItem()
                                .opacity(0.15)
                        }
                        .mask(
                            LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.8))
                        )
                    }
                    .frame(height: 250)
                }
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            
            VStack(alignment:.leading, spacing: 8) {
                Text("Recent Releases")
                    .titleSerifMini()
                
                EmptyEpisodeCell()
            }
            .frame(maxWidth:.infinity,alignment:.leading)
            
            VStack(alignment:.leading, spacing: 8) {
                Text("Favorites")
                    .titleSerifMini()
                
                EmptyEpisodeCell()
            }
            .frame(maxWidth:.infinity,alignment:.leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
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
