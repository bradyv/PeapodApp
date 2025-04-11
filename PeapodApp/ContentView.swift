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
            .onAppear {
                EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                    toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
                }
            }

            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                        toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
                    }
                }
            }
            .scrollDisabled(subscriptions.isEmpty)
            .refreshable {
                await withCheckedContinuation { continuation in
                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                        toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
                        continuation.resume()
                    }
                }
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
//        .toast()
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()
