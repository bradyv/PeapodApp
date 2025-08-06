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
    @EnvironmentObject var episodeSelectionManager: EpisodeSelectionManager
    @EnvironmentObject var player: AudioPlayerManager
    @State private var selectedEpisode: Episode? = nil
    var displayedInQueue: Bool = false
    var namespace: Namespace.ID
    var onTap: ((Episode) -> Void)?

    var body: some View {
        
        Group {
            if let episode = player.currentEpisode {
                let artwork = episode.episodeImage ?? episode.podcast?.image ?? ""
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
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .onTapGesture {
                        selectedEpisode = episode
                    }
                    
                    HStack {
                        Button(action: {
                            player.skipBackward(seconds: player.backwardInterval)
                            print("Seeking back")
                        }) {
                            Label("Go back", systemImage: "\(String(format: "%.0f", player.backwardInterval)).arrow.trianglehead.counterclockwise")
                        }
                        .disabled(!player.isPlaying)
                        
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
            }
//            } else {
//                HStack {
//                    Text("Nothing playing")
//                        .textBody()
//                        .frame(maxWidth:.infinity, alignment: .leading)
//
//                    HStack {
//                        Button(action: {
//                        }) {
//                            Label("Go back", systemImage: "\(String(format: "%.0f", player.backwardInterval)).arrow.trianglehead.counterclockwise")
//                        }
//                        .disabled(!player.isPlaying)
//
//                        Button(action: {
//                        }) {
//                            Image(systemName: "play.fill")
//                        }
//                        .disabled(!player.isPlaying)
//
//                        Button(action: {
//                        }) {
//                            Label("Go forward", systemImage: "\(String(format: "%.0f", player.forwardInterval)).arrow.trianglehead.clockwise")
//                        }
//                        .disabled(!player.isPlaying)
//                    }
//                }
//                .padding(.leading,16).padding(.trailing, 8)
//                .frame(maxWidth:.infinity, alignment:.leading)
//            }
        }
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode, namespace:namespace)
                .modifier(PPSheet())
        }
    }
}
