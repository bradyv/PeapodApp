//
//  OldEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-06.
//

import SwiftUI

struct OldEpisodes: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.airDate, order: .reverse)],
        predicate: NSPredicate(format: "(podcast = nil OR podcast.isSubscribed != YES) AND isSaved == NO AND isPlayed == NO"),
        animation: .interactiveSpring()
    )
    var old: FetchedResults<Episode>
    @State private var selectedEpisode: Episode? = nil
    @State private var showDeleteConfirmation = false
    var namespace: Namespace.ID
    
    private func deleteOldEpisodes() {
        for episode in old {
            context.delete(episode)
        }
        do {
            try context.save()
        } catch {
            print("Failed to delete old episodes: \(error)")
        }
    }
    
    var body: some View {
        if old.isEmpty {
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
                    ForEach(old, id: \.id) { episode in
                        EpisodeItem(episode: episode, savedView:true, namespace: namespace)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                    .sheet(item: $selectedEpisode) { episode in
                        EpisodeView(episode: episode, namespace: namespace)
                            .modifier(PPSheet(showOverlay: false))
                    }
                }
            }
            .padding()
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
