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
    @Environment(\.scenePhase) private var scenePhase
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest())
    var subscriptions: FetchedResults<Podcast>
    @State private var lastRefreshDate = Date.distantPast
    @State private var selectedEpisode: Episode? = nil
    @State private var episodeID = UUID()
    @StateObject private var opmlImportManager = OPMLImportManager()
    @State private var showFileBrowser: Bool = false
    @State private var selectedOPMLContent: String = ""
    @Namespace private var namespace

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
                            AudioPlayerManager.shared.togglePlayback(for: episode)
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
                        Spacer().frame(height:4)
                        if episodesViewModel.isLoading {
                            LoadingView
                                .transition(.opacity)
                        } else {
                            VStack(spacing: 32) {
                                QueueView()
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
            .navigationDestination(item: $selectedEpisode) { episode in
                EpisodeView(episode: episode)
                    .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        PodcastSearchView()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        QueueListView()
                    } label: {
                        Label("Up Next", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                    }
                    .labelStyle(.iconOnly)
                    
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
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
                    .frame(height: 450)
                }
                .frame(maxWidth:.infinity, alignment:.leading)
            }
            .frame(maxWidth:.infinity, alignment:.leading)
//
//            VStack(alignment:.leading, spacing: 8) {
//                Text("Recent Releases")
//                    .titleSerifMini()
//
//                EmptyEpisodeCell()
//            }
//            .frame(maxWidth:.infinity,alignment:.leading)
//
//            VStack(alignment:.leading, spacing: 8) {
//                Text("Favorites")
//                    .titleSerifMini()
//
//                EmptyEpisodeCell()
//            }
//            .frame(maxWidth:.infinity,alignment:.leading)
//
            VStack(alignment:.leading, spacing:8) {
                Text("Library")
                    .titleSerifMini()
                
                HStack(spacing: 16) {
                    let frame = (UIScreen.main.bounds.width - 80) / 3
                    ForEach(1...3, id:\.self) {_ in
                        SkeletonItem(width:frame,height:frame,cornerRadius:24)
                    }
                }
            }
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
    
    // Helper to find episode using Firebase episode ID format
    private func findEpisodeByFirebaseId(_ firebaseEpisodeID: String) {
        LogManager.shared.info("🔍 Searching for episode with Firebase ID (MD5 hash): \(firebaseEpisodeID)")
        
        // Fetch all subscribed podcasts
        let podcastRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        podcastRequest.predicate = NSPredicate(format: "isSubscribed == YES")
        
        do {
            let subscribedPodcasts = try context.fetch(podcastRequest)
            
            // Search through all episodes in subscribed podcasts
            for podcast in subscribedPodcasts {
                guard let feedUrl = podcast.feedUrl else { continue }
                
                let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                episodeRequest.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
                
                let episodes = try context.fetch(episodeRequest)
                
                for episode in episodes {
                    guard let guid = episode.guid else { continue }
                    
                    // Recreate the hash using the same logic as Firebase
                    let combined = "\(feedUrl)_\(guid)"
                    let hash = combined.md5Hash()
                    
                    if hash == firebaseEpisodeID {
                        LogManager.shared.info("✅ Found episode by hash match: \(episode.title ?? "Unknown")")
                        LogManager.shared.info("   Matched: \(feedUrl) + \(guid) = \(hash)")
                        selectedEpisode = episode
                        return
                    }
                }
            }
            
            LogManager.shared.error("❌ Could not find episode matching Firebase ID: \(firebaseEpisodeID)")
        } catch {
            LogManager.shared.error("❌ Error searching for episode: \(error)")
        }
    }
}
