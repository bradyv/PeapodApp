//
//  OldEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-06.
//

import SwiftUI

struct OldEpisodes: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @State private var selectedEpisode: Episode? = nil
    @State private var showDeleteConfirmation = false
    var namespace: Namespace.ID
    
    private func deleteOldEpisodes() {
        for episode in episodesViewModel.old {
            context.delete(episode)
        }
        do {
            try context.save()
        } catch {
            print("Failed to delete old episodes: \(error)")
        }
    }
    
    var body: some View {
        if episodesViewModel.old.isEmpty {
            VStack {
                Text("No old episodes to purge")
                    .titleCondensed()
            }
            .frame(maxWidth:.infinity, maxHeight:.infinity)
        } else {
            ScrollView {
                Spacer().frame(height:24)
                Text("Old episodes")
                    .titleSerif()
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("These episodes were stored during browsing, for podcasts that were never subscribed to. They can be safely purged from the database to free up space.")
                    .textBody()
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete All", systemImage: "trash")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                }
                
                LazyVStack {
                    ForEach(episodesViewModel.old, id: \.id) { episode in
                        EpisodeItem(episode: episode, savedView:true, namespace: namespace)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                    }
                }
            }
            .padding()
            .onAppear {
                context.refreshAllObjects()

                for episode in episodesViewModel.old {
                    if let podcast = episode.podcast {
                        context.refresh(podcast, mergeChanges: true)
                    }

                    let title = episode.title ?? "Unknown Title"
                    let podcastTitle = episode.podcast?.title ?? "None"
                    let isSubscribed = episode.podcast?.isSubscribed == true ? "YES" : "NO"

                    print("Episode: \(title)")
                    print("  Podcast: \(podcastTitle)")
                    print("  isSubscribed: \(isSubscribed)")
                    print("  isSaved: \(episode.isSaved ? "YES" : "NO")")
                    print("  isPlayed: \(episode.isPlayed ? "YES" : "NO")")
                    print("  Podcast feedUrl: \(episode.podcast?.feedUrl ?? "none")")
                    print("  Podcast objectID: \(episode.podcast?.objectID.uriRepresentation().absoluteString ?? "none")")
                    print("---")
                }
            }
            .ignoresSafeArea(edges: .all)
            .alert("Delete all old episodes?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteOldEpisodes()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently remove all old episodes from the database.")
            }
        }
    }
}
