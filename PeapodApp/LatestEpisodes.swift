//
//  LatestEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-04.
//

import SwiftUI

struct LatestEpisodes: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var toastManager: ToastManager
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.airDate, order: .reverse)],
        predicate: NSPredicate(format: "podcast != nil AND podcast.isSubscribed == YES AND isPlayed == NO AND playbackPosition == 0 AND nowPlaying = NO"),
        animation: .interactiveSpring()
    )
    var latest: FetchedResults<Episode>
    @State private var selectedEpisode: Episode? = nil
    @State private var selectedDetent: PresentationDetent = .medium
    var namespace: Namespace.ID
    
    var body: some View {
        ScrollView {
            FadeInView(delay: 0.2) {
                Text("Unplayed Episodes")
                    .titleSerif()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading).padding(.top,24)
            }
            
            FadeInView(delay: 0.4) {
                LazyVStack(alignment: .leading) {
                    ForEach(latest, id: \.id) { episode in
                        NavigationLink {
                            PPPopover {
                                EpisodeView(episode: episode, namespace: namespace)
                            }
                            .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
                        } label: {
                            EpisodeItem(episode: episode, namespace: namespace)
                                .lineLimit(3)
                                .padding(.bottom, 24)
                                .padding(.horizontal)
                                .matchedTransitionSource(id: episode.id, in: namespace)
                        }
                    }
                }
            }
        }
        .toast()
        .maskEdge(.top)
        .maskEdge(.bottom)
        .onAppear {
            EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
//                toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
            }
        }
    }
}
