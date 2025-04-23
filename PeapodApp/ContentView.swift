//
//  ContentView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var toastManager: ToastManager
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "isSubscribed == YES"),
        animation: .default
    ) var subscriptions: FetchedResults<Podcast>
    @State private var showSettings = false
    
    var body: some View {
        ZStack(alignment:.topTrailing) {
            NowPlayingSplash()
            ScrollView {
                FadeInView(delay: 0.1) {
                    QueueView()
                }
                FadeInView(delay: 0.2) {
                    LibraryView()
                }
                FadeInView(delay: 0.3) {
                    SubscriptionsView()
                }
                
                Spacer().frame(height:96)
            }
            .maskEdge(.top)
            .maskEdge(.bottom)
            .ignoresSafeArea(.all)
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
                    .modifier(PPSheet(bg:false))
            }
            
            NowPlaying()
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
//        .NowPlaying()
//        .toast()
    }
}
