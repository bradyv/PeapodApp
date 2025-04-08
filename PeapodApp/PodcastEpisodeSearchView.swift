//
//  PodcastEpisodeSearchView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-07.
//

import SwiftUI

struct PodcastEpisodeSearchView: View {
    @Environment(\.managedObjectContext) private var context
    var podcast: Podcast
    @Binding var showSearch: Bool
    @Binding var selectedEpisode: Episode?

    @FetchRequest private var latest: FetchedResults<Episode>
    @State private var query = ""
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
            // Search bar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .resizable()
                        .frame(width: 12, height: 12)
                        .opacity(0.35)

                    TextField("Find an episode of \(podcast.title ?? "Podcast title")", text: $query)
                        .focused($isTextFieldFocused)
                        .textRow()

                    if !query.isEmpty {
                        Button(action: {
                            query = ""
                            isTextFieldFocused = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.surface)
                .cornerRadius(44)

                Button(action: {
                    isTextFieldFocused = false
                    showSearch.toggle()
                    query = ""
                }) {
                    Text("Cancel")
                }
                .textBody()
            }

            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(filteredEpisodes, id: \.id) { episode in
                        EpisodeItem(episode: episode)
                            .padding(.bottom, 12)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                }
                .padding(.top, 8)
            }
            .sheet(item: $selectedEpisode) { episode in
                EpisodeView(episode: episode)
                    .modifier(PPSheet())
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
