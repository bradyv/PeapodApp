//
//  ContentView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData
import Kingfisher

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var toastManager: ToastManager
    @Namespace var episodeAnimation
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "isSubscribed == YES"),
        animation: .default
    ) var subscriptions: FetchedResults<Podcast>
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "nowPlayingItem == YES"),
        animation: .default
    ) var nowPlaying: FetchedResults<Episode>
    @State private var showSettings = false
    
    var body: some View {
        ZStack(alignment:.topTrailing) {
            GeometryReader { outerGeo in
                let safeWidth = max(outerGeo.size.width, 1)
                if let episode = nowPlaying.first(where: { !$0.isFault && !$0.isDeleted && $0.id != nil }) {
                    VStack {
                        KFImage(URL(string: episode.episodeImage ?? episode.podcast?.image ?? ""))
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                    startPoint: .top,
                                    endPoint: .init(x: 0.5, y: 0.7)
                                )
                            )
                            .allowsHitTesting(false)
                        Spacer()
                    }
                    .ignoresSafeArea(.all)
                }
                
                ScrollView {
                    Spacer().frame(height: nowPlaying.count > 0 ? safeWidth / 2 : 64)
                    FadeInView(delay: 0.2) {
                        QueueView(animationNamespace: episodeAnimation)
                    }
                    FadeInView(delay: 0.3) {
                        LibraryView()
                    }
                    FadeInView(delay: 0.4) {
                        SubscriptionsView()
                    }
                }
                .onAppear {
                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
                    //                EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                    //                    toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
                    //                }
                }
                .ignoresSafeArea(.all)
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
                    //                await withCheckedContinuation { continuation in
                    //                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                    //                        toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
                    //                        continuation.resume()
                    //                    }
                    //                }
                }
                
                VStack(alignment:.trailing) {
                    Button(action: {
                        showSettings.toggle()
                    }) {
                        Label("Settings", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(PPButton(type: .transparent, colorStyle: .monochrome, iconOnly: true))
                    
                    Spacer()
                }
                .frame(maxWidth:.infinity, alignment:.trailing)
                .padding(.horizontal)
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .modifier(PPSheet())
                }
            }
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
//        .toast()
    }
}
