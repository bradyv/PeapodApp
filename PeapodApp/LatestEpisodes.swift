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
    @State private var selectedEpisode: Episode? = nil
    @State private var selectedDetent: PresentationDetent = .medium
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:24)
            FadeInView(delay: 0.2) {
                Text("Latest Episodes")
                    .titleSerif()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading).padding(.top,24)
            }
            
            FadeInView(delay: 0.4) {
                LazyVStack(alignment: .leading) {
                    ForEach(latest, id: \.id) { episode in
                        EpisodeItem(episode: episode)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                    .sheet(item: $selectedEpisode) { episode in
                        EpisodeView(episode: episode, selectedDetent: $selectedDetent)
                            .modifier(PPSheet(shortStack: true, detent: $selectedDetent))
                            .onChange(of: selectedDetent) { newValue in
                                if newValue == .medium {
                                    selectedEpisode = nil
                                }
                            }
                    }
                }
            }
        }
        .toast()
        .maskEdge(.bottom)
        .onAppear {
            EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
//                toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
            }
        }
        .ignoresSafeArea(edges: .all)
    }
}
