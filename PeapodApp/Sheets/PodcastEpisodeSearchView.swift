//
//  PodcastEpisodeSearchView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-07.
//

import SwiftUI
import CoreData

struct PodcastEpisodeSearchView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    var podcast: Podcast
    @Binding var showSearch: Bool
    @Binding var selectedEpisode: Episode?
    @State private var episodes: [Episode] = []
    @State private var query = ""
    @State private var hasMoreEpisodes = true
    @State private var isLoadingMoreEpisodes = false
    @FocusState private var isTextFieldFocused: Bool

    init(podcast: Podcast, showSearch: Binding<Bool>, selectedEpisode: Binding<Episode?>) {
        self.podcast = podcast
        self._showSearch = showSearch
        self._selectedEpisode = selectedEpisode
    }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                if filteredEpisodes.isEmpty && !query.isEmpty {
                    FadeInView(delay: 0.2) {
                        VStack {
                            Text("No results for \(query)")
                                .textBody()
                            
                            // Show option to load more episodes if available
                            if hasMoreEpisodes && !isLoadingMoreEpisodes {
                                VStack {
                                    Button("Load more episodes") {
                                        loadMoreEpisodes()
                                    }
                                    .buttonStyle(PPButton(type:.filled, colorStyle: .tinted))
                                    .padding(.top, 8)
                                }
                                .frame(maxWidth:.infinity)
                            } else if isLoadingMoreEpisodes && query.isEmpty {
                                VStack {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading more episodes...")
                                            .textDetail()
                                    }
                                    .padding(.top, 8)
                                }
                                .frame(maxWidth:.infinity)
                            }
                        }
                        .padding(.top,32)
                    }
                } else {
                    LazyVStack(alignment: .leading) {
                        ForEach(filteredEpisodes, id: \.id) { episode in
                            EpisodeItem(episode: episode, showActions: false)
                                .lineLimit(3)
                                .padding(.bottom, 24)
                                .onTapGesture {
                                    selectedEpisode = episode
                                }
                                .contextMenu {
                                    Button {
                                        withAnimation {
                                            if episode.isQueued {
                                                removeFromQueue(episode, episodesViewModel: episodesViewModel)
                                            } else {
                                                toggleQueued(episode, episodesViewModel: episodesViewModel)
                                            }
                                        }
                                    } label: {
                                        Label(episode.isQueued ? "Remove from Up Next" : "Add to Up Next", systemImage: episode.isQueued ? "archivebox" : "text.append")
                                    }
                                    Button {
                                        withAnimation {
                                            toggleFav(episode, episodesViewModel: episodesViewModel)
                                        }
                                    } label: {
                                        Label(episode.isFav ? "Remove from Favorites" : "Add to Favorites", systemImage: episode.isFav ? "heart.slash" : "heart")
                                    }
                                }
                        }
                        
                        // 🆕 Show "Load more" button for search results too
                        if hasMoreEpisodes && !isLoadingMoreEpisodes && !query.isEmpty {
                            VStack(spacing: 8) {
                                Text("Don't see what you're looking for?")
                                    .textDetail()
                                
                                Button("Load more episodes") {
                                    loadMoreEpisodes()
                                }
                                .buttonStyle(PPButton(type:.filled, colorStyle: .tinted))
                                .padding(.vertical, 8)
                            }
                            .frame(maxWidth: .infinity)
                        } else if isLoadingMoreEpisodes && !query.isEmpty {
                            VStack {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading more episodes...")
                                        .textDetail()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                            .frame(maxWidth:.infinity)
                        }
                        
                        // Show "Load more" button at the bottom (when not searching)
                        if hasMoreEpisodes && !isLoadingMoreEpisodes && query.isEmpty {
                            VStack(spacing: 8) {
                                Text("Showing \(episodes.count) episodes")
                                    .textDetail()
                                
                                Button("Load more episodes") {
                                    loadMoreEpisodes()
                                }
                                .buttonStyle(PPButton(type:.transparent, colorStyle: .monochrome))
                                .padding(.vertical, 16)
                            }
                            .frame(maxWidth: .infinity)
                        } else if isLoadingMoreEpisodes {
                            VStack {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading next 50 episodes...")
                                        .textDetail()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                            .frame(maxWidth:.infinity)
                        } else if !hasMoreEpisodes && query.isEmpty && episodes.count > 50 {
                            // Show "all loaded" message
                            VStack {
                                Text("All \(episodes.count) episodes loaded")
                                    .textDetail()
                                    .padding(.vertical, 16)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .contentMargins(16, for: .scrollContent)
        }
        .background(Color.background)
        .searchable(text: $query, isPresented: $showSearch, placement: .toolbar, prompt: "Find an episode of \(podcast.title ?? "this podcast")")
        .navigationTitle(podcast.title ?? "Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
        .onAppear {
            loadEpisodesForPodcast()
            checkIfMoreEpisodesAvailable()
        }
    }

    private var filteredEpisodes: [Episode] {
        if query.isEmpty {
            return episodes
        } else {
            return episodes.filter {
                $0.title?.localizedCaseInsensitiveContains(query) == true ||
                $0.episodeDescription?.localizedCaseInsensitiveContains(query) == true
            }
        }
    }
    
    // Load episodes using podcastId instead of relationship
    private func loadEpisodesForPodcast() {
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        
        do {
            episodes = try context.fetch(request)
            LogManager.shared.info("📱 Loaded \(episodes.count) episodes for podcast")
        } catch {
            LogManager.shared.error("❌ Failed to load episodes: \(error)")
            episodes = []
        }
    }
    
    // Check if more episodes might be available
    private func checkIfMoreEpisodesAvailable() {
        // If we have 25 or more episodes, there might be more
        // (since initial load is limited to 25)
        hasMoreEpisodes = episodes.count >= 25
    }
    
    // Load next batch of 50 episodes
    private func loadMoreEpisodes() {
        guard !isLoadingMoreEpisodes else { return }
        
        isLoadingMoreEpisodes = true
        
        EpisodeRefresher.loadNextBatchOfEpisodes(for: podcast, context: context) { newCount, moreAvailable in
            DispatchQueue.main.async {
                self.isLoadingMoreEpisodes = false
                self.hasMoreEpisodes = moreAvailable
                
                if newCount > 0 {
                    // Reload episodes to show new ones
                    self.loadEpisodesForPodcast()
                    LogManager.shared.info("✅ Loaded \(newCount) more episodes. More available: \(moreAvailable)")
                } else {
                    LogManager.shared.info("ℹ️ No new episodes loaded - might be at the end")
                }
            }
        }
    }
}
