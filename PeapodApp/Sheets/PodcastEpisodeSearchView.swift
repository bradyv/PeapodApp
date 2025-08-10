//
//  PodcastEpisodeSearchView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-07.
//

import SwiftUI

struct PodcastEpisodeSearchView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    var podcast: Podcast
    @Binding var showSearch: Bool
    @Binding var selectedEpisode: Episode?

    @FetchRequest private var latest: FetchedResults<Episode>
    @State private var query = ""
    @State private var hasMoreEpisodes = true // Track if more episodes available
    @State private var isLoadingMoreEpisodes = false // Loading state for incremental loads
    @FocusState private var isTextFieldFocused: Bool

    init(podcast: Podcast, showSearch: Binding<Bool>, selectedEpisode: Binding<Episode?>) {
        self.podcast = podcast
        self._showSearch = showSearch
        self._selectedEpisode = selectedEpisode
        _latest = FetchRequest<Episode>(
            sortDescriptors: [SortDescriptor(\.airDate, order: .reverse)],
            predicate: NSPredicate(format: "podcast == %@", podcast),
            animation: .interactiveSpring()
        )
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
                            EpisodeItem(episode: episode, showActions: true)
                                .lineLimit(3)
                                .padding(.bottom, 24)
                                .onTapGesture {
                                    selectedEpisode = episode
                                }
                        }
                        
                        // 🆕 Show "Load more" button for search results too (not just when query is empty)
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
                                Text("Showing \(latest.count) episodes")
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
                        } else if !hasMoreEpisodes && query.isEmpty && latest.count > 50 {
                            // Show "all loaded" message
                            VStack {
                                Text("All \(latest.count) episodes loaded")
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
        .searchable(text: $query, isPresented: $showSearch, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find an episode of \(podcast.title ?? "this podcast")")
        .navigationTitle(podcast.title ?? "Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
        .onAppear {
            // Check if we have more episodes available
            checkIfMoreEpisodesAvailable()
        }
    }

    private var filteredEpisodes: [Episode] {
        if query.isEmpty {
            return Array(latest)
        } else {
            return latest.filter {
                $0.title?.localizedCaseInsensitiveContains(query) == true ||
                $0.episodeDescription?.localizedCaseInsensitiveContains(query) == true
            }
        }
    }
    
    // Check if more episodes might be available
    private func checkIfMoreEpisodesAvailable() {
        // If we have 50 or more episodes, there might be more
        // This is just a heuristic - the actual check happens when loading
//        hasMoreEpisodes = latest.count >= 50
        hasMoreEpisodes = true
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
                    LogManager.shared.info("✅ Loaded \(newCount) more episodes. More available: \(moreAvailable)")
                } else {
                    LogManager.shared.info("ℹ️ No new episodes loaded - might be at the end")
                }
            }
        }
    }
}
