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
                    }
                }
            }
            .contentMargins(16, for: .scrollContent)
        }
        .background(Color.background)
        .searchable(text: $query, isPresented: $showSearch, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find an episode of \(podcast.title ?? "this podcast")")
//        .toolbar {
//            ToolbarItem(placement:.topBarLeading) {
//                Button(action: {
//                    dismiss()
//                }) {
//                    Label("Cancel", systemImage: "chevron.down")
//                }
//            }
//        }
        .navigationTitle(podcast.title ?? "Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode, namespace:namespace)
                .modifier(PPSheet())
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
}
