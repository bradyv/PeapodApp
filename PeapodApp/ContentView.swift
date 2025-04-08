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
    @EnvironmentObject var fetcher: PodcastFetcher
    
    var body: some View {
        ZStack {
            ScrollView {
                QueueView()
                LibraryView()
                SubscriptionsView()
//                Welcome()
            }
            .onAppear {
                EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
                }
            }
            .refreshable {
                EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
            }
            
//            NowPlaying()
        }
        .background(Color.background)
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()
