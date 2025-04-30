//
//  LatestEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-04.
//

import SwiftUI

struct LatestEpisodes: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var toastManager: ToastManager
    @State private var selectedEpisode: Episode? = nil
    @State private var showAll = true
    var namespace: Namespace.ID
    
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
                    ForEach(showAll ? episodesViewModel.latest : episodesViewModel.unplayed, id: \.id) { episode in
                        NavigationLink {
                            PPPopover(pushView:false) {
                                EpisodeView(episode: episode, namespace: namespace)
                            }
                            .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
                            .interactiveDismissDisabled(false)
                        } label: {
                            EpisodeItem(episode: episode, namespace: namespace)
                                .lineLimit(3)
                                .padding(.bottom, 24)
                                .padding(.horizontal)
                        }
                        .animation(.easeOut(duration: 0.2), value: showAll)
                    }
                }
            }
        }
        .onAppear {
            episodesViewModel.fetchLatest()
        }
        .toast()
        .maskEdge(.top)
        .maskEdge(.bottom)
//        .refreshable {
//            EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
////                toastManager.show(message: "Refreshed all episodes", icon: "sparkles")
//            }
//        }
    }
}
