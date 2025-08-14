//
//  NowPlaying.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-06.
//

import SwiftUI
import Kingfisher

struct NowPlaying: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var player: AudioPlayerManager
    @Environment(\.tabViewBottomAccessoryPlacement) var placement
    @State private var selectedEpisode: Episode? = nil
    @State private var episodeID = UUID()
    @State private var queue: [Episode] = []
    var onTap: ((Episode) -> Void)?
    
    private var firstQueueEpisode: Episode? {
        queue.first
    }

    var body: some View {
        Group {
//            if let episode = player.currentEpisode {
            if let episode = firstQueueEpisode {
                let artwork = episode.episodeImage ?? episode.podcast?.image ?? ""
                HStack {
                    HStack {
                        ArtworkView(url: artwork, size: 36, cornerRadius: 18, tilt: false)
                        
                        VStack(alignment:.leading) {
                            Text(episode.podcast?.title ?? "Podcast title")
                                .textDetail()
                                .lineLimit(1)
                            
                            Text(episode.title ?? "Episode title")
                                .textBody()
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEpisode = episode
                    }
                    
                    HStack {
                        Button(action: {
                            player.togglePlayback(for: episode)
                            print("Playing episode")
                        }) {
                            if player.isLoading {
                                PPSpinner(color: Color.heading)
                            } else if player.isPlaying {
                                Image(systemName: "pause")
                            } else {
                                Image(systemName: "play.fill")
                            }
                        }
                        
                        Button(action: {
                            player.skipForward(seconds: player.forwardInterval)
                            print("Seeking forward")
                        }) {
                            Label("Go forward", systemImage: "\(String(format: "%.0f", player.forwardInterval)).arrow.trianglehead.clockwise")
                        }
                        .disabled(!player.isPlaying)
                    }
                }
                .padding(.leading,4)
                .padding(.trailing, 8)
                .frame(maxWidth:.infinity, alignment:.leading)
            } else {
                HStack {
                    Text("Nothing playing")
                        .textBody()
                        .frame(maxWidth:.infinity, alignment: .leading)

                    HStack {
                        Button(action: {
                        }) {
                            Image(systemName: "play.fill")
                        }
                        .disabled(player.isPlaying)
                        
                        Button(action: {
                        }) {
                            Label("Go forward", systemImage: "\(String(format: "%.0f", player.forwardInterval)).arrow.trianglehead.clockwise")
                        }
                        .disabled(!player.isPlaying)
                    }
                }
                .padding(.leading,16).padding(.trailing, 8)
                .frame(maxWidth:.infinity, alignment:.leading)
            }
        }
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
        .id(episodeID)
        .onChange(of: firstQueueEpisode?.id) { _ in
            episodeID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            // Refresh queue when Core Data changes
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
