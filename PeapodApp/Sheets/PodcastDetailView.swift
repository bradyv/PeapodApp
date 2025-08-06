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
    @FocusState var showSearch: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var showDebugTools = false
    @State private var showConfirm = false
    @State private var showNotificationRequest = false
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var query = ""
    @FocusState private var isTextFieldFocused: Bool
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
    
    private var filteredEpisodes: [Episode] {
        if query.isEmpty {
            return Array(episodes)
        } else {
            return episodes.filter {
                $0.title?.localizedCaseInsensitiveContains(query) == true ||
                $0.episodeDescription?.localizedCaseInsensitiveContains(query) == true
            }
        }
    }

    var body: some View {
        ZStack {
            if let podcast {
                SplashImage(image: podcast.image ?? "")
                
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
                    
                    Spacer().frame(height:8)
                    
                    Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
                        .textBody()
                        .lineLimit(showFullDescription ? nil :  3)
                        .frame(maxWidth:.infinity)
                        .onTapGesture {
                            withAnimation {
                                showFullDescription.toggle()
                            }
                        }
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.15), value: showFullDescription)
                    
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
                    
                    Text(query.isEmpty ? "Episodes" : "Results for \(query)")
                        .titleSerifMini()
                        .frame(maxWidth:.infinity, alignment:.leading)
                    
                    LazyVStack(alignment: .leading) {
                        ForEach(filteredEpisodes, id: \.id) { episode in
                            NavigationLink {
                                EpisodeView(episode:episode,namespace:namespace)
                                    .navigationTransition(.zoom(sourceID: episode.guid, in: namespace))
                            } label: {
                                EpisodeItem(episode: episode, showActions: true, namespace: namespace)
                                    .lineLimit(3)
                                    .padding(.bottom, 24)
                            }
                            .matchedTransitionSource(id: episode.guid, in: namespace)
                        }
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
                .coordinateSpace(name: "scroll")
                .contentMargins(16, for: .scrollContent)
                .frame(maxWidth:.infinity)
                .searchable(text: $query, prompt: "Find an episode of \(podcast.title ?? "this podcast")")
                .searchFocused($showSearch)
                .onAppear {
                    Task.detached(priority: .background) {
                        await ColorTintManager.applyTintIfNeeded(to: podcast, in: context)
                        await EpisodeRefresher.refreshPodcastEpisodes(for: podcast, context: context)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                subscribeButton()
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
    
    @ViewBuilder
    func subscribeButton() -> some View {
    
        Button(action: {
            // Toggle subscription state
            podcast!.isSubscribed.toggle()
            
            // Show toast message
            toastManager.show(message: podcast!.isSubscribed ? "Followed \(podcast!.title ?? "")" : "Unfollowed \(podcast!.title ?? "")", icon: podcast!.isSubscribed ? "checkmark.circle" : "minus.circle")
            
            if podcast!.isSubscribed {
                // Add latest episode to queue when subscribing
                if let latest = (podcast!.episode as? Set<Episode>)?
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
                   let allEpisodes = podcast!.episode as? Set<Episode> {
                    for episode in allEpisodes where (queuePlaylist.items as? Set<Episode>)?.contains(episode) == true {
                        queuePlaylist.removeFromItems(episode)
                        episode.isQueued = false
                        episode.queuePosition = -1
                    }
                }
            }

            // Save Core Data changes
            do {
                try podcast?.managedObjectContext?.save()
                
                // 🔥 Sync subscription changes with Firebase after Core Data save
                SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
                
            } catch {
                LogManager.shared.error("❌ Failed to save subscription change: \(error)")
            }
        }) {
            Text(podcast!.isSubscribed ? "Unfollow" : "Follow")
                .if(!podcast!.isSubscribed, transform: { $0.foregroundStyle(.heading) })
                .titleCondensed()
        }
        .if(!podcast!.isSubscribed, transform: { $0.buttonStyle(.glassProminent) })
    }
}
