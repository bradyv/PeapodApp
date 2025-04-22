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
    @State private var selectedDetent: PresentationDetent = .medium
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
            SearchBox(
                query: $query,
                label: "Find an episode of \(podcast.title ?? "Podcast title")",
                onCancel: {
                    isTextFieldFocused = false
                    query = ""
                    showSearch.toggle()
                }
            )

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
                    Text(query.isEmpty ? "Episodes" : "Results for \(query)")
                        .headerSection()
                        .frame(maxWidth:.infinity, alignment:.leading)
                    
                    LazyVStack(alignment: .leading) {
                        ForEach(filteredEpisodes, id: \.id) { episode in
                            EpisodeItem(episode: episode)
                                .lineLimit(3)
                                .padding(.bottom, 12)
                                .onTapGesture {
                                    selectedEpisode = episode
                                }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .sheet(item: $selectedEpisode) { episode in
                EpisodeView(episode: episode, selectedDetent: $selectedDetent)
                    .modifier(PPSheet(showOverlay: false))
                    .presentationDetents([.medium, .large], selection: $selectedDetent)
                    .presentationContentInteraction(.resizes)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isTextFieldFocused = true
            }
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
