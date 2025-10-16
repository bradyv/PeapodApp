//
//  PodcastDetailView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import FeedKit
import CoreData
import Kingfisher
import Pow

struct PodcastDetailView: View {
    let feedUrl: String
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var toastManager: ToastManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @FetchRequest var podcastResults: FetchedResults<Podcast>
    @State private var episodes: [Episode] = []
    @State var showFullDescription: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showDebugTools = false
    @State private var showConfirm = false
    @State private var query = ""
    @State private var showSearch = false
    @State private var isLoading = true
    @State private var loadedPodcast: Podcast? = nil
    @State private var selectedEpisodeForNavigation: Episode? = nil
    @Namespace private var namespace
    
    var podcast: Podcast? { loadedPodcast ?? podcastResults.first }

    init(feedUrl: String) {
        self.feedUrl = feedUrl
        _podcastResults = FetchRequest<Podcast>(
            entity: Podcast.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "feedUrl == %@", feedUrl),
            animation: .default
        )
    }

    var body: some View {
        Group {
            if let podcast = podcast {
                ScrollView {
                    Color.clear
                        .frame(height: 1)
                        .trackScrollOffset("scroll") { value in
                            scrollOffset = value
                        }
                
                    ArtworkView(url: podcast.image ?? "", size: 128, cornerRadius: 24, tilt: true)
                        .onTapGesture(count: 5) {
                            withAnimation {
                                showDebugTools.toggle()
                            }
                        }
                        .changeEffect(.spin, value: podcast.isSubscribed)
                
                    VStack {
                        Text(podcast.title ?? "Podcast title")
                            .titleSerif()
                            .multilineTextAlignment(.center)
                        
                        Spacer().frame(height:32)
                        
                        if showDebugTools {
                            Button(action: {
                                showConfirm = true
                            }) {
                                Label("Delete Podcast", systemImage: "trash")
                            }
                            .buttonStyle(PPButton(type:.transparent, colorStyle: .monochrome))
                            .alert(
                                "Delete Podcast",
                                isPresented: $showConfirm,
                                presenting: podcast
                            ) { podcast in
                                Button("Delete", role: .destructive) {
                                    // Delete all episodes for this podcast first
                                    let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                                    episodeRequest.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
                                    
                                    if let podcastEpisodes = try? context.fetch(episodeRequest) {
                                        for episode in podcastEpisodes {
                                            context.delete(episode)
                                        }
                                    }
                                    
                                    context.delete(podcast)
                                    try? context.save()
                                    
                                    // 🔥 Sync subscription changes with Firebase after deletion
                                    SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: { podcast in
                                Text("Are you sure you want to delete this podcast from Core Data? This action cannot be undone.")
                            }
                        }
                        
                        NavigationLink {
                            PodcastEpisodeSearchView(podcast: podcast, showSearch: $showSearch)
                        } label: {
                            HStack(alignment:.center) {
                                Text("Episodes")
                                    .titleSerifMini()
                                
                                Image(systemName: "chevron.right")
                                    .textDetailEmphasis()
                            }
                            .frame(maxWidth:.infinity, alignment: .leading)
                        }
                        
                        LazyVStack(spacing: 24) {
                            ForEach(episodes.prefix(3), id: \.id) { episode in
                                NavigationLink {
                                    EpisodeView(episode:episode)
                                        .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
                                } label: {
                                    EpisodeCell(
                                        data: EpisodeCellData(from: episode),
                                        episode: episode,
                                        showPodcast: false
                                    )
                                    .matchedTransitionSource(id: episode.id, in: namespace)
                                    .frame(maxWidth:.infinity)
                                }
                            }
                        }
                        
                        Spacer().frame(height:24)
                        
                        Divider()
                        
                        Spacer().frame(height:32)
                        
                        VStack(spacing:8) {
                            Text("About")
                                .titleSerifMini()
                                .frame(maxWidth:.infinity, alignment:.leading)
                            
                            Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
                                .textBody()
                                .lineLimit(nil)
                                .frame(maxWidth:.infinity, alignment:.leading)
                        
                        }
                        .frame(maxWidth:.infinity, alignment:.leading)
                    }
                }
                .background {
                    let frame = UIScreen.main.bounds.width
                    SplashImage(image: podcast.image ?? "")
                        .offset(y:-200)
                }
                .background(Color.background)
                .scrollEdgeEffectStyle(.soft, for: .all)
                .coordinateSpace(name: "scroll")
                .contentMargins(16, for: .scrollContent)
                .scrollClipDisabled(true)
                .frame(maxWidth:.infinity)
                .onAppear {
                    Task.detached(priority: .background) {
                        await EpisodeRefresher.refreshPodcastEpisodes(for: podcast, context: context, limitToRecent: true)
                    }
                }
                .navigationTitle(podcast.title ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.principal) {
                        Text(scrollOffset < -250 ? "\(podcast.title ?? "") " : " ")
                            .font(.system(.headline, design: .serif))
                    }
                    
                    ToolbarItem {
                        subscribeButton()
                    }
                }
                // 🔥 ADD: Listen for Core Data changes and refresh episodes
                .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
                    Task { @MainActor in
                        refreshEpisodes()
                    }
                }
            } else if isLoading {
                LoadingView
            } else {
                VStack {
                    Text("Unable to load podcast")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth:.infinity, maxHeight:.infinity)
            }
        }
        .toolbar {
            if !episodesViewModel.queue.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    MiniPlayer()
                    Spacer()
                    MiniPlayerButton()
                }
            }
        }
        .onAppear {
            // Load podcast if not already available
            if podcast == nil && isLoading {
                PodcastLoader.loadFeed(from: feedUrl, context: context) { podcast in
                    self.loadedPodcast = podcast
                    self.isLoading = false
                    refreshEpisodes()
                }
            } else if podcast != nil {
                isLoading = false
                refreshEpisodes()
            }
        }
    }
    
    // 🔥 ADD: Manual episode refresh function to avoid @FetchRequest issues
    @MainActor
    private func refreshEpisodes() {
        guard let podcast = podcast else { return }
        
        Task {
            let result: [Episode] = await withCheckedContinuation { continuation in
                context.perform {
                    let request: NSFetchRequest<Episode> = Episode.fetchRequest()
                    request.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
                    request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
                    
                    do {
                        let fetchedEpisodes = try self.context.fetch(request)
                        continuation.resume(returning: fetchedEpisodes)
                    } catch {
                        LogManager.shared.error("⚠️ Failed to fetch episodes for podcast: \(error)")
                        continuation.resume(returning: [])
                    }
                }
            }
            
            self.episodes = result
        }
    }
    
    @ViewBuilder
    var LoadingView: some View {
        ScrollView {
            Color.clear
                .frame(height: 1)
                .trackScrollOffset("scroll") { value in
                    scrollOffset = value
                }
            
            Spacer().frame(height:24)
            
            SkeletonItem(width:128, height:128, cornerRadius:24)
                .rotationEffect(.degrees(2))
            
            Spacer().frame(height:16)
            
            SkeletonItem(width:128, height:34)
            
            Spacer().frame(height:36)
            
            Text("Episodes")
                .titleSerifMini()
                .frame(maxWidth:.infinity, alignment:.leading)
            
            VStack(spacing:24) {
                ForEach(1...3, id: \.self) { _ in
                    EmptyEpisodeCell()
                }
            }
        }
        .disabled(true)
        .contentMargins(.horizontal,16, for:.scrollContent)
        .frame(maxWidth:.infinity, maxHeight:.infinity)
    }
    
    @ViewBuilder
    func subscribeButton() -> some View {
        Button(action: {
            guard let podcast = podcast else { return }
            
            // Toggle subscription state
            podcast.isSubscribed.toggle()
            
            // Show toast message
            toastManager.show(message: podcast.isSubscribed ? "Followed \(podcast.title ?? "")" : "Unfollowed \(podcast.title ?? "")", icon: podcast.isSubscribed ? "checkmark.circle" : "minus.circle")
            
            if podcast.isSubscribed {
                // FIXED: Add latest episode to queue when subscribing using boolean approach
                if let latest = episodes.first {
                    if !latest.isPlayed {
                        latest.isQueued = true
                        LogManager.shared.info("🔥 Queued latest episode when subscribing: \(latest.title ?? "Unknown")")
                    }
                }
            }
                
//            } else {
//                // Remove episodes from playlists when unsubscribing
//                // Preserves episodes with meaningful playback data
//                removeEpisodesFromPlaylists(for: podcast)
//            }

            // Save Core Data changes
            do {
                try podcast.managedObjectContext?.save()
                
                // 🔥 Sync subscription changes with Firebase after Core Data save
                SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
                
                // Refresh episodes after subscription change
                refreshEpisodes()
                
            } catch {
                LogManager.shared.error("⚠️ Failed to save subscription change: \(error)")
            }
        }) {
            Text(podcast?.isSubscribed == true ? "Unfollow" : "Follow")
                .if(podcast?.isSubscribed != true, transform: { $0.foregroundStyle(.white) })
                .titleCondensed()
        }
        .if(podcast?.isSubscribed != true, transform: { $0.buttonStyle(.glassProminent) })
    }
    
    // Helper function to intelligently handle episodes when unsubscribing
    // Uses same logic as AppDelegate's cleanup: preserves episodes with meaningful playback data
    private func removeEpisodesFromPlaylists(for podcast: Podcast) {
        // Get all episodes for this podcast
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        
        do {
            let podcastEpisodes = try context.fetch(request)
            var removedCount = 0
            var preservedCount = 0
            
            for episode in podcastEpisodes {
                // Check if episode has meaningful playback data (same logic as AppDelegate)
                let hasMeaningfulPlayback = episode.isPlayed ||
                                           episode.isFav ||
                                           episode.isQueued ||
                                           episode.playbackPosition > 300 // 5 minutes
                
                if hasMeaningfulPlayback {
                    // Keep the episode but remove it from queue
                    episode.isQueued = false
                    preservedCount += 1
                    LogManager.shared.info("📌 Preserved episode with meaningful playback: \(episode.title ?? "Unknown")")
                } else {
                    // Remove episode entirely - no meaningful interaction
                    context.delete(episode)
                    removedCount += 1
                }
            }
            
            // Save the changes
            try context.save()
            LogManager.shared.info("✅ Unsubscribed from \(podcast.title ?? "Unknown"): removed \(removedCount) episodes, preserved \(preservedCount) with meaningful playback")
            
        } catch {
            LogManager.shared.error("⚠️ Failed to remove episodes from playlists: \(error)")
        }
    }
}
