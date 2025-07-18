//
//  PodcastDetailView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

//
//  PodcastDetailView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import FeedKit
import CoreData

struct PodcastDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var toastManager: ToastManager
    @FetchRequest var podcastResults: FetchedResults<Podcast>
    @State private var selectedEpisode: Episode? = nil
    @State var showFullDescription: Bool = false
    @State private var showSearch = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showDebugTools = false
    @State private var showConfirm = false
    @State private var showNotificationRequest = false
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    var podcast: Podcast? { podcastResults.first }
    var namespace: Namespace.ID
    var episodes: [Episode] {
        (podcast?.episode as? Set<Episode>)?
            .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) }) ?? []
    }

    init(feedUrl: String, namespace: Namespace.ID) {
        _podcastResults = FetchRequest<Podcast>(
            entity: Podcast.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "feedUrl == %@", feedUrl),
            animation: .default
        )
        self.namespace = namespace
    }

    var body: some View {
        ZStack {
            if let podcast {
                SplashImage(image: podcast.image ?? "")
                
                if showSearch {
                    VStack(alignment:.leading) {
                        PodcastEpisodeSearchView(podcast: podcast, showSearch: $showSearch, selectedEpisode: $selectedEpisode, namespace: namespace)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                } else {
                    ZStack {
                        ScrollView {
                            Color.clear
                                .frame(height: 1)
                                .trackScrollOffset("scroll") { value in
                                    scrollOffset = value
                                }
                            
                            Spacer().frame(height:128)
                            
                            FadeInView(delay: 0.2) {
                                VStack(alignment:.leading) {
                                    Text(podcast.title ?? "Podcast title")
                                        .titleSerif()
                                }
                                .frame(maxWidth:.infinity, alignment:.leading)
                                .padding(.bottom,12)
                            }
                            
                            FadeInView(delay: 0.3) {
                                Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
                                    .textBody()
                                    .lineLimit(showFullDescription ? nil :  4)
                                    .frame(maxWidth:.infinity, alignment:.leading)
                                    .onTapGesture {
                                        withAnimation {
                                            showFullDescription.toggle()
                                        }
                                    }
                                    .transition(.opacity)
                                    .animation(.easeOut(duration: 0.15), value: showFullDescription)
                                
                                Spacer().frame(height:24)
                            }
                            
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
                                    presenting: podcast // Optional if you want access to the object inside the alert
                                ) { podcast in
                                    Button("Delete", role: .destructive) {
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
                            
                            LazyVStack(alignment: .leading) {
                                if let latestEpisode = episodes.first {
                                    FadeInView(delay: 0.4) {
                                        Text("Latest Episode")
                                            .headerSection()
                                    }
                                    
                                    FadeInView(delay: 0.5) {
                                        EpisodeItem(episode: latestEpisode, showActions: true, namespace: namespace)
                                            .lineLimit(3)
                                            .padding(.bottom, 24)
                                    }
                                }
                                
                                let remainingEpisodes = Array(episodes.dropFirst())
                                
                                if !remainingEpisodes.isEmpty {
                                    FadeInView(delay: 0.6) {
                                        Text("Episodes")
                                            .headerSection()
                                    }
                                    
                                    FadeInView(delay: 0.7) {
                                        ForEach(remainingEpisodes, id: \.id) { episode in
                                            EpisodeItem(episode: episode, showActions: true, namespace: namespace)
                                                .lineLimit(3)
                                                .padding(.bottom, 24)
                                        }
                                    }
                                }
                            }
                        }
                        .coordinateSpace(name: "scroll")
                        .contentMargins(16, for: .scrollContent)
                        .maskEdge(.top)
                        .maskEdge(.bottom)
                        .transition(.opacity)
                        .frame(maxWidth:.infinity)
                        .onAppear {
                            Task.detached(priority: .background) {
                                await ColorTintManager.applyTintIfNeeded(to: podcast, in: context)
                                await EpisodeRefresher.refreshPodcastEpisodes(for: podcast, context: context)
                            }
                        }
                        
                        FadeInView(delay: 0.2) {
                            VStack(alignment:.leading) {
                                Spacer().frame(height:16)
                                let minSize: CGFloat = 64
                                let maxSize: CGFloat = 172
                                let threshold: CGFloat = 72
                                let shrink = max(minSize, min(maxSize, maxSize + min(0, scrollOffset - threshold)))
                                
                                ArtworkView(url:podcast.image ?? "", size: shrink, cornerRadius:16)
                                    .animation(.easeOut(duration: 0.1), value: shrink)
                                    .onTapGesture(count: 5) {
                                        withAnimation {
                                            showDebugTools.toggle()
                                        }
                                    }
                                Spacer()
                            }
                            .frame(maxWidth:.infinity, alignment:.leading)
                            .padding(.horizontal)
                            
                            VStack {
                                Spacer().frame(height:16)
                                HStack(alignment:.top) {
                                    Spacer()
                                    
                                    HStack {
                                        Button(action: {
                                            showSearch.toggle()
                                        }) {
                                            Label("Search \(podcast.title ?? "episodes")", systemImage: "text.magnifyingglass")
                                        }
                                        .buttonStyle(PPButton(type: .transparent, colorStyle: .monochrome, iconOnly: true))
                                        
                                        Button(action: {
                                            // Toggle subscription state
                                            podcast.isSubscribed.toggle()
                                            
                                            // Show toast message
                                            toastManager.show(message: podcast.isSubscribed ? "Followed \(podcast.title ?? "")" : "Unfollowed \(podcast.title ?? "")", icon: podcast.isSubscribed ? "checkmark.circle" : "minus.circle")
                                            
                                            if podcast.isSubscribed {
                                                // Add latest episode to queue when subscribing
                                                if let latest = (podcast.episode as? Set<Episode>)?
                                                    .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) })
                                                    .first {
                                                    toggleQueued(latest)
                                                }
                                                
                                                checkAndShowNotificationRequest()
                                                
                                            } else {
                                                // Remove all of this podcast's episodes from the Queue playlist when unsubscribing
                                                let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
                                                request.predicate = NSPredicate(format: "name == %@", "Queue")

                                                if let queuePlaylist = try? context.fetch(request).first,
                                                   let allEpisodes = podcast.episode as? Set<Episode> {
                                                    for episode in allEpisodes where (queuePlaylist.items as? Set<Episode>)?.contains(episode) == true {
                                                        queuePlaylist.removeFromItems(episode)
                                                        episode.isQueued = false
                                                        episode.queuePosition = -1
                                                    }
                                                }
                                            }

                                            // Save Core Data changes
                                            do {
                                                try podcast.managedObjectContext?.save()
                                                
                                                // 🔥 Sync subscription changes with Firebase after Core Data save
                                                SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
                                                
                                            } catch {
                                                LogManager.shared.error("❌ Failed to save subscription change: \(error)")
                                            }
                                        }) {
                                            Text(podcast.isSubscribed ? "Unfollow" : "Follow")
                                        }
                                        .buttonStyle(PPButton(type: podcast.isSubscribed ? .transparent : .filled, colorStyle: .monochrome))
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .animation(.interactiveSpring(duration: 0.25), value: showSearch)
        .onAppear {
            checkNotificationStatus()
        }
        .fullScreenCover(isPresented: $showNotificationRequest) {
            RequestNotificationsView(
                onComplete: {
                    showNotificationRequest = false
                },
                namespace: namespace
            )
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationAuthStatus = settings.authorizationStatus
            }
        }
    }
    
    private func checkAndShowNotificationRequest() {
        // Only show if notifications haven't been granted AND haven't been explicitly denied
        if notificationAuthStatus == .notDetermined {
            showNotificationRequest = true
        }
    }
}
