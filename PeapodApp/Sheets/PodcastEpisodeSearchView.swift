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
    @EnvironmentObject var nowPlayingManager: NowPlayingVisibilityManager
    var podcast: Podcast
    @Binding var showSearch: Bool
    @Binding var selectedEpisode: Episode?

    @FetchRequest private var latest: FetchedResults<Episode>
    @State private var query = ""
    @State private var hasLoadedAllEpisodes = false
    @State private var isLoadingAllEpisodes = false
    @FocusState private var isTextFieldFocused: Bool
    var namespace: Namespace.ID

    init(podcast: Podcast, showSearch: Binding<Bool>, selectedEpisode: Binding<Episode?>, namespace: Namespace.ID) {
        self.podcast = podcast
        self._showSearch = showSearch
        self._selectedEpisode = selectedEpisode
        self.namespace = namespace
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
                            
                            // Show option to load more episodes if not all are loaded
                            if !hasLoadedAllEpisodes && !isLoadingAllEpisodes {
                                VStack {
                                    Button("Load all episodes") {
                                        loadAllEpisodes()
                                    }
                                    .buttonStyle(PPButton(type:.filled, colorStyle: .tinted))
                                    .padding(.top, 8)
                                }
                                .frame(maxWidth:.infinity)
                            } else if isLoadingAllEpisodes {
                                VStack {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading all episodes...")
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
                            EpisodeItem(episode: episode, showActions: true, namespace: namespace)
                                .lineLimit(3)
                                .padding(.bottom, 24)
                                .onTapGesture {
                                    selectedEpisode = episode
                                }
                        }
                        
                        // Show "Load more" button at the bottom if not all episodes are loaded
                        if !hasLoadedAllEpisodes && !isLoadingAllEpisodes && query.isEmpty {
                            VStack {
                                Button("Load all episodes") {
                                    loadAllEpisodes()
                                }
                                .buttonStyle(PPButton(type:.transparent, colorStyle: .monochrome))
                                .padding(.vertical, 16)
                            }
                            .frame(maxWidth: .infinity)
                        } else if isLoadingAllEpisodes {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading remaining episodes...")
                                    .textDetail()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
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
            EpisodeView(episode: episode, namespace:namespace)
                .modifier(PPSheet())
        }
        .onAppear {
            // Check if we might have all episodes already
            checkIfAllEpisodesLoaded()
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
    
    private func checkIfAllEpisodesLoaded() {
        // Heuristic: If we have more than 50 episodes, we probably have loaded all
        // Or you could store a flag on the Podcast entity to track this
        if latest.count > 50 {
            hasLoadedAllEpisodes = true
        }
    }
    
    private func loadAllEpisodes() {
        guard !isLoadingAllEpisodes else { return }
        
        isLoadingAllEpisodes = true
        
        EpisodeRefresher.fetchAllRemainingEpisodes(for: podcast, context: context) {
            DispatchQueue.main.async {
                isLoadingAllEpisodes = false
                hasLoadedAllEpisodes = true
                LogManager.shared.info("✅ Finished loading all episodes for \(podcast.title ?? "podcast")")
            }
        }
    }
}
