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
            Spacer().frame(height:24)
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
                            NavigationLink {
                                PPPopover(pushView:false) {
                                    EpisodeView(episode: episode, namespace: namespace)
                                }
                                .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
                            } label: {
                                EpisodeItem(episode: episode, namespace: namespace)
                                    .lineLimit(3)
                                    .padding(.bottom, 12)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .maskEdge(.bottom)
            .ignoresSafeArea(edges:.bottom)
        }
        .onAppear {
            nowPlayingManager.isVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isTextFieldFocused = true
            }
        }
        .onDisappear {
            nowPlayingManager.isVisible = true
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
