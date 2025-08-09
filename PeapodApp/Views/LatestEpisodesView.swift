//
//  LatestEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-04.
//

import SwiftUI

struct LatestEpisodesView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var toastManager: ToastManager
    @State private var selectedEpisode: Episode? = nil
    @State private var showAll = true
    @State private var selectedPodcast: Podcast? = nil
    
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
                        EpisodeItem(episode: episode, showActions: true)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                            .animation(.easeOut(duration: 0.2), value: showAll)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                }
            }
        }
        .navigationTitle(showAll ? "Recent Releases" : "Unplayed")
        .background(Color.background)
        .toolbar {
            ToolbarItem {
                Button(action: {
                    showAll.toggle()
                }) {
                    Label("Filter", systemImage:"line.3.horizontal.decrease")
                }
                .if(!showAll, transform: { $0.buttonStyle(.glassProminent)})
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .toast()
        .refreshable {
            EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
                toastManager.show(message: "Peapod is up to date", icon: "sparkles")
                LogManager.shared.info("✨ Refreshed latest episodes")
            }
        }
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
    }
}

struct LatestEpisodesMini: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @Environment(\.managedObjectContext) private var context
    @State private var selectedEpisode: Episode? = nil
    @State private var selectedPodcast: Podcast? = nil
    
    var body: some View {
        VStack {
            Spacer().frame(height:44)
            
            if !episodesViewModel.latest.isEmpty {
                NavigationLink {
                    LatestEpisodesView()
                        .navigationTitle("Recent Releases")
                } label: {
                    HStack(alignment:.center) {
                        Text("Recent Releases")
                            .titleSerifMini()
                            .padding(.leading)
                        
                        Image(systemName: "chevron.right")
                            .textDetailEmphasis()
                    }
                    .frame(maxWidth:.infinity, alignment: .leading)
                }
                
                LazyVStack(alignment: .leading) {
                    ForEach(episodesViewModel.latest.prefix(3), id: \.id) { episode in
                        EpisodeItem(episode: episode, showActions: true)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                }
            }
        }
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
    }
}
