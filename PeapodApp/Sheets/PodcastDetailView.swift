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
import Kingfisher

struct PodcastDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var toastManager: ToastManager
    @FetchRequest var podcastResults: FetchedResults<Podcast>
    @State private var selectedEpisode: Episode? = nil
    @State var showFullDescription: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showDebugTools = false
    @State private var showConfirm = false
    @State private var showNotificationRequest = false
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var query = ""
    @State private var showSearch = false
//    @FocusState private var showSearch: Bool
    
    var podcast: Podcast? { podcastResults.first }
    var episodes: [Episode] {
        (podcast?.episode as? Set<Episode>)?
            .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) }) ?? []
    }

    init(feedUrl: String) {
        _podcastResults = FetchRequest<Podcast>(
            entity: Podcast.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "feedUrl == %@", feedUrl),
            animation: .default
        )
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
        if let podcast {
            ScrollView {
                Color.clear
                    .frame(height: 1)
                    .trackScrollOffset("scroll") { value in
                        scrollOffset = value
                    }
                
//                    if !showSearch {
                    ArtworkView(url: podcast.image ?? "", size: 128, cornerRadius: 24, tilt: true)
                        .onTapGesture(count: 5) {
                            withAnimation {
                                showDebugTools.toggle()
                            }
                        }
                    
                    Text(podcast.title ?? "Podcast title")
                        .titleSerif()
                        .multilineTextAlignment(.center)
                    
//                    Spacer().frame(height:8)
//                    
//                    Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
//                        .textBody()
//                        .multilineTextAlignment(showFullDescription ? .leading : .center)
//                        .lineLimit(showFullDescription ? nil :  3)
//                        .frame(maxWidth:.infinity)
//                        .onTapGesture {
//                            withAnimation {
//                                showFullDescription.toggle()
//                            }
//                        }
//                        .transition(.opacity)
//                        .animation(.easeOut(duration: 0.15), value: showFullDescription)
                        
                        Spacer().frame(height:32)
                
//                        Button {
//                            withAnimation {
//                                showSearch = true
//                                isSearching = true
//                            }
//                        } label: {
//                            Label("Find an episode of \(podcast.title ?? "this podcast")", systemImage: "magnifyingglass")
//                                .textBody()
//                                .padding(.vertical,4)
//                                .frame(maxWidth:.infinity)
//                                .lineLimit(1)
//                        }
//                        .buttonStyle(.glass)
//
//                        Spacer().frame(height:32)
//                    }
                
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
                
//                Text(query.isEmpty ? "Episodes" : "Results for \"\(query)\"")
//                    .titleSerifMini()
//                    .frame(maxWidth:.infinity, alignment:.leading)
                
                if let latestEpisode = filteredEpisodes.first {
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
                    ForEach(filteredEpisodes.prefix(4).dropFirst(), id: \.id) { episode in
                        EpisodeItem(episode: episode, showActions: true)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                }
                
                VStack(spacing:8) {
                    Text("About")
                        .titleSerifMini()
                        .frame(maxWidth:.infinity, alignment:.leading)
                    
                    Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
                        .textBody()
                        .lineLimit(nil)
//                        .multilineTextAlignment(showFullDescription ? .leading : .center)
                    //                    .lineLimit(showFullDescription ? nil :  3)
                        .frame(maxWidth:.infinity)
                    //                    .onTapGesture {
                    //                        withAnimation {
                    //                            showFullDescription.toggle()
                    //                        }
                    //                    }
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.15), value: showFullDescription)
                }
            }
            .background {
                SplashImage(image: podcast.image ?? "")
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .coordinateSpace(name: "scroll")
            .contentMargins(16, for: .scrollContent)
            .frame(maxWidth:.infinity)
//            .searchable(text: $query, prompt: "Find an episode of \(podcast.title ?? "this podcast")")
//                .if(showSearch, transform: { $0.searchable(text: $query, isPresented: $showSearch, prompt: "Find an episode of \(podcast.title ?? "this podcast")") })
            .onAppear {
                checkNotificationStatus()
                
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
                .if(!podcast!.isSubscribed, transform: { $0.foregroundStyle(.white) })
                .titleCondensed()
        }
        .if(!podcast!.isSubscribed, transform: { $0.buttonStyle(.glassProminent) })
    }
}
