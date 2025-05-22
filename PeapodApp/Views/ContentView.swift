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

//    @State private var showOnboarding = true // bv debug

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
                    let now = Date()
                    if now.timeIntervalSince(lastRefreshDate) > 300 { // only refresh if >5min since last refresh
                        lastRefreshDate = now
                        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        let now = Date()
                        if now.timeIntervalSince(lastRefreshDate) > 300 { // only refresh if >5min since last refresh
                            lastRefreshDate = now
                            EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
                        }
                    }
                }
                .scrollDisabled(subscriptions.isEmpty)
                .refreshable {
                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
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
                requestNotificationPermissions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapEpisodeNotification)) { notification in
            if let id = notification.object as? String {
                let context = PersistenceController.shared.container.viewContext
                let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                fetchRequest.fetchLimit = 1
                
                if let foundEpisode = try? context.fetch(fetchRequest).first {
                    // Instead of setting tappedEpisode, use the episodeSelectionManager
                    episodeSelectionManager.selectEpisode(foundEpisode)
                } else {
                    print("❌ Could not find episode for id \(id)")
                }
            }
        }
//        .toast()
    }
    
    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        print("✅ Local notifications authorized")
                    } else if let error = error {
                        print("❌ Notification permission error: \(error.localizedDescription)")
                    } else {
                        print("❌ Notification permission denied")
                    }
                }
            }
        }
    }
    
    private func checkPendingNotification() {
        // Check if we have a pending notification episode ID
        if let pendingID = AppDelegate.pendingNotificationEpisodeID {
            // Clear it immediately to prevent duplicate handling
            AppDelegate.pendingNotificationEpisodeID = nil
            
            // Fetch and open the episode
            let context = PersistenceController.shared.container.viewContext
            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", pendingID)
            fetchRequest.fetchLimit = 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Small delay to ensure UI is ready
                if let foundEpisode = try? context.fetch(fetchRequest).first {
                    episodeSelectionManager.selectEpisode(foundEpisode)
                } else {
                    print("❌ Could not find episode for id \(pendingID)")
                }
            }
        }
    }
}
