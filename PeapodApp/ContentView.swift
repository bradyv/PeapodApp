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
    @EnvironmentObject var syncMonitor: CloudSyncMonitor
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "isSubscribed == YES"),
        animation: .default
    ) var subscriptions: FetchedResults<Podcast>
    
    var body: some View {
        ZStack {
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
            }
            .onChange(of: syncMonitor.isSyncing) { newValue in
                print("🧪 isSyncing changed: \(newValue)")
                
                if newValue {
                    toastManager.show(message: "Restoring data from iCloud...", icon: "icloud", duration: nil, loading: true)
                } else {
                    toastManager.show(message: "iCloud sync complete", icon: "checkmark.circle", duration: nil)
                    toastManager.dismissAfterDelay(1.0)
                }
            }
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
            
//            NowPlaying()
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
        .toast()
    }
}
