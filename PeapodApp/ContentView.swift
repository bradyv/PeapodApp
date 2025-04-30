//
//  ContentView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Namespace var namespace
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var toastManager: ToastManager
    @EnvironmentObject var nowPlayingManager: NowPlayingVisibilityManager
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest())
    var subscriptions: FetchedResults<Podcast>
    @StateObject private var episodesViewModel: EpisodesViewModel = EpisodesViewModel.placeholder()
    @State private var showSettings = false
    @State private var currentEpisodeID: String? = nil
    @State private var path = NavigationPath()
    @State private var selectedEpisode: Episode?
    @State private var lastRefreshDate = Date.distantPast
    @State private var tappedEpisodeID: String?
    @State private var tappedEpisode: Episode?

//    @State private var showOnboarding = true // bv debug
    @AppStorage("showOnboarding") private var showOnboarding: Bool = true

    var body: some View {
        ZStack {
            if showOnboarding {
                WelcomeView(showOnboarding: $showOnboarding, namespace:namespace)
            } else {
                ZStack {
                    NavigationStack(path: $path) {
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
                        .navigationDestination(for: Episode.self) { episode in
                            PPPopover(pushView:false) {
                                EpisodeView(episode: episode, namespace: namespace) // Now Playing destination
                            }
                            .navigationTransition(.zoom(sourceID: "nowplaying", in: namespace))
                        }
                        
                        NavigationLink(isActive: Binding(
                            get: { tappedEpisode != nil },
                            set: { newValue in if !newValue { tappedEpisode = nil } }
                        )) {
                            if let episode = tappedEpisode {
                                PPPopover(pushView: false) {
                                    EpisodeView(episode: episode, namespace: namespace)
                                }
                                .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
                            }
                        } label: {
                            EmptyView()
                        }
                        .hidden()
                    }
                    .environmentObject(episodesViewModel)
                    
                    ZStack(alignment: .bottom) {
                        if nowPlayingManager.isVisible {
                            NowPlaying(namespace: namespace) { episode in
                                path.append(episode)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: nowPlayingManager.isVisible)
                }
                .onAppear {
                    let context = PersistenceController.shared.container.viewContext
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
                .onReceive(NotificationCenter.default.publisher(for: .didTapEpisodeNotification)) { notification in
                    if let id = notification.object as? String {
                        let context = PersistenceController.shared.container.viewContext
                        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                        fetchRequest.fetchLimit = 1

                        if let foundEpisode = try? context.fetch(fetchRequest).first {
                            tappedEpisode = foundEpisode
                        } else {
                            print("❌ Could not find episode for id \(id)")
                        }
                    }
                }
            }
        }
        .onAppear {
            if episodesViewModel.context == nil { // not yet initialized properly
                episodesViewModel.setup(context: context)
            }
        }
//        .toast()
    }
}
