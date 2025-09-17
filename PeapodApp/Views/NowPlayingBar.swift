//
//  NowPlayingBar.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData

struct NowPlayingButton: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var player: AudioPlayerManager
    @State private var queue: [Episode] = []
    
    private var displayEpisode: Episode? {
        // Show currently playing episode, or first queue item if nothing playing
        return player.currentEpisode ?? queue.first
    }
    
    var body: some View {
        if let episode = displayEpisode {
            Button(action: {
                player.togglePlayback(for: episode)
            }) {
                if player.isLoadingEpisode(episode) {
                    PPSpinner(color: Color.heading)
                } else {
                    Image(systemName: player.isPlayingEpisode(episode) ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(Color.heading)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
                loadQueue()
            }
            .onAppear {
                loadQueue()
            }
        }
    }
    
    private func loadQueue() {
        queue = fetchEpisodesInPlaylist(named: "Queue", context: context)
    }
}

struct NowPlayingBar: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var player: AudioPlayerManager
    @State private var queue: [Episode] = []
    @State private var episodeID = UUID()
    @Namespace private var namespace
    
    private var displayEpisode: Episode? {
        // Show currently playing episode, or first queue item if nothing playing
        return player.currentEpisode ?? queue.first
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if let episode = displayEpisode {
                let artwork = episode.episodeImage ?? episode.podcast?.image ?? ""
                HStack {
                    NavigationLink {
                        EpisodeView(episode: episode)
                            .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
                    } label: {
                        HStack {
                            ArtworkView(url: artwork, size: 36, cornerRadius: 18, tilt: false)
                                .matchedGeometryEffect(id: episode.id, in: namespace)
                            
                            VStack(alignment:.leading) {
                                Text(episode.podcast?.title ?? "Podcast title")
                                    .textDetail()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                Text(episode.title ?? "Episode title")
                                    .textBody()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth:.infinity, alignment: .leading)
                        }
                        .frame(maxWidth:.infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth:.infinity, alignment:.leading)
            }
        }
        .frame(maxWidth:.infinity)
        .id(episodeID)
        .onChange(of: displayEpisode?.id) { _ in
            episodeID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            loadQueue()
        }
        .onAppear {
            loadQueue()
        }
    }
    
    private func loadQueue() {
        queue = fetchEpisodesInPlaylist(named: "Queue", context: context)
    }
}
