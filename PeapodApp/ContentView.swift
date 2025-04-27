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
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "isSubscribed == YES"),
        animation: .default
    ) var subscriptions: FetchedResults<Podcast>
    @State private var showSettings = false
    @State private var currentEpisodeID: String? = nil
    @State private var path = NavigationPath()
    @State private var selectedEpisode: Episode?

    var body: some View {
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
                        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
                        //                EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                        //                    toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
                        //                }
                    }
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        if newPhase == .active {
                            EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
                            //                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                            //                        toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
                            //                    }
                        }
                    }
                    .scrollDisabled(subscriptions.isEmpty)
                    .refreshable {
                        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
                        print("refreshed")
                        //                await withCheckedContinuation { continuation in
                        //                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                        //                        toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
                        //                        continuation.resume()
                        //                    }
                        //                }
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
            }
            
            ZStack(alignment: .bottom) {
                if nowPlayingManager.isVisible {
                    NowPlaying(namespace: namespace) { episode in
                        path.append(episode)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: nowPlayingManager.isVisible)
        }
//        .toast()
    }
}
