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
        predicate: NSPredicate(format: "podcast != nil AND podcast.isSubscribed == YES"),
        animation: .interactiveSpring()
    )
    var latest: FetchedResults<Episode>
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.airDate, order: .reverse)],
        predicate: NSPredicate(format: "podcast != nil AND podcast.isSubscribed == YES AND isPlayed == NO AND playbackPosition == 0 AND nowPlaying = NO"),
        animation: .interactiveSpring()
    )
    var unplayed: FetchedResults<Episode>
    @State private var selectedEpisode: Episode? = nil
    var namespace: Namespace.ID
    @State private var showAll = true
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:24)
            FadeInView(delay: 0.2) {
                HStack {
                    Text("Latest Episodes")
                        .titleSerif()
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            showAll.toggle()
                        }
                    } label: {
                        Label(showAll ? "All" : "Unplayed", systemImage: "chevron.compact.down")
                    }
                    .labelStyle(.titleOnly)
                    .foregroundStyle(Color.accentColor)
                    .textBody()
                }
                .padding(.horizontal).padding(.top,24)
            }
            
            FadeInView(delay: 0.4) {
                LazyVStack(alignment: .leading) {
                    ForEach(showAll ? latest : unplayed, id: \.id) { episode in
                        NavigationLink {
                            PPPopover(pushView:false) {
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
                        .animation(.easeOut(duration: 0.2), value: showAll)
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
