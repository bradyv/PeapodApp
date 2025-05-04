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
    @State private var selectedPodcast: Podcast? = nil
    var namespace: Namespace.ID
    
    // Computed property to get unique podcasts
    private var uniquePodcasts: [Podcast] {
        let episodes = showAll ? episodesViewModel.latest : episodesViewModel.unplayed
        let podcastsSet = Set(episodes.compactMap { $0.podcast })
        return Array(podcastsSet).sorted(by: { $0.title ?? "" < $1.title ?? "" })
    }
    
    // Computed property to get filtered episodes
    private var filteredEpisodes: [Episode] {
        let episodes = showAll ? episodesViewModel.latest : episodesViewModel.unplayed
        
        if let selectedPodcast = selectedPodcast {
            return episodes.filter { $0.podcast?.id == selectedPodcast.id }
        } else {
            return episodes
        }
    }
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:24)
            FadeInView(delay: 0.1) {
                HStack {
                    Text("Latest Episodes")
                        .titleSerif()
                    
                    Spacer()
                    
//                    Button {
//                        withAnimation {
//                            showAll.toggle()
//                        }
//                    } label: {
//                        Label(showAll ? "All" : "Unplayed", systemImage: "chevron.compact.down")
//                    }
//                    .labelStyle(.titleOnly)
//                    .foregroundStyle(Color.accentColor)
//                    .textBody()
                }
                .padding(.horizontal).padding(.top,24)
            }
            
            FadeInView(delay: 0.2) {
                ZStack {
                    VStack {
                        Spacer()
                        Divider()
                            .frame(height:1)
                            .background(Color.surface)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing:16) {
                            VStack {
                                Button {
                                    withAnimation {
                                        selectedPodcast = nil
                                    }
                                } label: {
                                    VStack {
                                        Text("All Podcasts")
                                            .foregroundStyle(Color.heading)
                                            .textBody()
                                    }
                                }
                                
                                Spacer()
                                
                                Divider()
                                    .frame(height:1)
                                    .background(Color.heading)
                                    .opacity(selectedPodcast == nil ? 1 : 0)
                            }
                            .opacity(selectedPodcast == nil ? 1 : 0.5)
                            
                            // Show unique podcasts
                            ForEach(uniquePodcasts, id: \.id) { podcast in
                                VStack {
                                    Button {
                                        withAnimation {
                                            if selectedPodcast?.id == podcast.id {
                                                // Deselect if tapping the same podcast
                                                selectedPodcast = nil
                                            } else {
                                                selectedPodcast = podcast
                                            }
                                        }
                                    } label: {
                                        VStack {
                                            ArtworkView(url: podcast.image ?? "", size: 24, cornerRadius: 4)
                                        }
                                    }
                                    
                                    Divider()
                                        .frame(height:1)
                                        .background(Color.heading)
                                        .opacity(selectedPodcast?.id == podcast.id ? 1 : 0)
                                }
                                .opacity(selectedPodcast?.id == podcast.id ? 1 : 0.5)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer().frame(height:24)
            }
            
            if filteredEpisodes.isEmpty {
                VStack(spacing: 16) {
                    Spacer().frame(height: 50)
                    Image(systemName: "rectangle.stack.badge.xmark")
                        .font(.title)
                        .foregroundColor(.gray)
                    Text("No episodes found")
                        .foregroundColor(.gray)
                    
                    Button {
                        selectedPodcast = nil
                    } label: {
                        Text("Show all episodes")
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVStack(alignment: .leading) {
                    ForEach(filteredEpisodes, id: \.id) { episode in
                        EpisodeItem(episode: episode, namespace: namespace)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
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
