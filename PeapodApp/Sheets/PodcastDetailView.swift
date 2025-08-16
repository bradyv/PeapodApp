//
//  PodcastDetailView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import FeedKit
import CoreData
import Kingfisher

struct PodcastDetailView: View {
    let feedUrl: String
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var toastManager: ToastManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @FetchRequest var podcastResults: FetchedResults<Podcast>
    @State private var episodes: [Episode] = []
    @State private var selectedEpisode: Episode? = nil
    @State var showFullDescription: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showDebugTools = false
    @State private var showConfirm = false
    @State private var query = ""
    @State private var showSearch = false
    @State private var isLoading = true
    @State private var loadedPodcast: Podcast? = nil
    
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
                        .buttonStyle(ShadowButton())
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
                    
                    if let latestEpisode = episodes.first {
                        VStack {
                            VStack {
                                Text("Latest Episode")
                                    .titleSerifMini()
                                    .frame(maxWidth:.infinity, alignment:.leading)
                                
                                EpisodeItem(episode: latestEpisode, showActions: true)
                                    .lineLimit(3)
                                    .onTapGesture {
                                        selectedEpisode = latestEpisode
                                    }
                            }
                            .padding()
                        }
                        .background {
                            KFImage(URL(string: latestEpisode.episodeImage ?? latestEpisode.podcast?.image ?? ""))
                                .resizable()
                                .aspectRatio(contentMode:.fill)
                                .blur(radius:50)
                                .mask(
                                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                                   startPoint: .top, endPoint: .bottom)
                                )
                                .opacity(0.5)
                        }
                        .clipShape(RoundedRectangle(cornerRadius:16))
                        .glassEffect(in: .rect(cornerRadius:16))
                    }
                    
                    Spacer().frame(height:24)
                    
                    NavigationLink {
                        PodcastEpisodeSearchView(podcast: podcast, showSearch: $showSearch, selectedEpisode: $selectedEpisode)
                    } label: {
                        HStack(alignment:.center) {
                            Text("Episodes")
                                .titleSerifMini()
                            
                            Image(systemName: "chevron.right")
                                .textDetailEmphasis()
                        }
                        .frame(maxWidth:.infinity, alignment: .leading)
                    }
                    
                    LazyVStack(alignment: .leading) {
                        ForEach(episodes.prefix(4).dropFirst(), id: \.id) { episode in
                            EpisodeItem(episode: episode, showActions: true)
                                .lineLimit(3)
                                .padding(.bottom, 24)
                                .onTapGesture {
                                    selectedEpisode = episode
                                }
                                .environmentObject(episodesViewModel)
                        }
                    }
                    
                    VStack(spacing:8) {
                        Text("About")
                            .titleSerifMini()
                            .frame(maxWidth:.infinity, alignment:.leading)
                        
                        Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
                            .textBody()
                            .lineLimit(nil)
                            .frame(maxWidth:.infinity)
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.15), value: showFullDescription)
                    }
                }
                .background {
                    SplashImage(image: podcast.image ?? "")
                }
                .background(Color.background)
                .scrollEdgeEffectStyle(.soft, for: .all)
                .coordinateSpace(name: "scroll")
                .contentMargins(16, for: .scrollContent)
                .frame(maxWidth:.infinity)
                .onAppear {
                    Task.detached(priority: .background) {
                        await EpisodeRefresher.refreshPodcastEpisodes(for: podcast, context: context, limitToRecent: true)
                    }
                }
                .sheet(item: $selectedEpisode) { episode in
                    EpisodeView(episode: episode)
                        .modifier(PPSheet())
                }
                .navigationTitle(scrollOffset < -194 ? "\(podcast.title ?? "")" : "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
                VStack {
                    ProgressView("Loading...")
                }
                .frame(maxWidth:.infinity, maxHeight:.infinity)
            } else {
                VStack {
                    Text("Unable to load podcast")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth:.infinity, maxHeight:.infinity)
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
                    latest.isQueued = true
                    LogManager.shared.info("🔥 Queued latest episode when subscribing: \(latest.title ?? "Unknown")")
                }
                
            } else {
                // Remove all of this podcast's episodes from all playlists when unsubscribing
                removeAllEpisodesFromPlaylists(for: podcast)
            }

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
    
    // Helper function to remove all episodes from playlists when unsubscribing
    private func removeAllEpisodesFromPlaylists(for podcast: Podcast) {
        // Get all episodes for this podcast
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        
        do {
            let podcastEpisodes = try context.fetch(request)
            
            // Clear all boolean states for episodes from this podcast
            for episode in podcastEpisodes {
                episode.isQueued = false
                episode.isPlayed = false
                episode.isFav = false
                
                // Also reset playback position
                episode.playbackPosition = 0
            }
            
            // Save the changes
            try context.save()
            LogManager.shared.info("✅ Removed all episodes from playlists for podcast: \(podcast.title ?? "Unknown")")
            
        } catch {
            LogManager.shared.error("⚠️ Failed to remove episodes from playlists: \(error)")
        }
    }
}
