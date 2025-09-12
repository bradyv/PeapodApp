//
//  NowPlayingBar.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData

struct NowPlayingBar: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var player: AudioPlayerManager
    @State private var query = ""
    @State private var queue: [Episode] = []
    @State private var episodeID = UUID()
    @State private var rotateTrigger = false
    @Namespace private var namespace
    @Binding var selectedEpisodeForNavigation: Episode?
    
    private var firstQueueEpisode: Episode? {
        queue.first
    }
    
    var body: some View {
       NowPlayingBar
    }
    
    @ViewBuilder
    var NowPlayingBar: some View {
        VStack(alignment: .leading) {
            if let episode = firstQueueEpisode {
                let artwork = episode.episodeImage ?? episode.podcast?.image ?? ""
                HStack {
                    Button {
                        selectedEpisodeForNavigation = episode
                    } label: {
                        HStack {
                            ArtworkView(url: artwork, size: 36, cornerRadius: 18, tilt: false)
                            
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
                    
                    HStack {
                        Button(action: {
                            player.togglePlayback(for: episode)
                            print("Playing episode")
                        }) {
                            if player.isLoading {
                                PPSpinner(color: Color.heading)
                            } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .contentTransition(.symbolEffect(.replace))
                                    .foregroundStyle(Color.heading)
                            }
                        }
                        
                        Button(action: {
                            rotateTrigger.toggle()
                            player.skipForward(seconds: player.forwardInterval)
                            print("Seeking forward")
                        }) {
                            Label("Go forward", systemImage: "\(String(format: "%.0f", player.forwardInterval)).arrow.trianglehead.clockwise")
                                .symbolEffect(.rotate.byLayer, options: .nonRepeating.speed(10), value: rotateTrigger)
                                .foregroundStyle(player.isPlaying ? Color.heading : Color.surface)
                        }
                        .disabled(!player.isPlaying)
                        .labelStyle(.iconOnly)
                    }
                }
                .frame(maxWidth:.infinity, alignment:.leading)
            }
//            } else {
//                HStack {
//                    Text("Nothing up next")
//                        .textBody()
//                        .frame(maxWidth:.infinity, alignment: .leading)
//                    
//                    ZStack {
//                        HStack {
//                            Button(action: {
//                            }) {
//                                Image(systemName: "play.fill")
//                            }
//                            .disabled(player.isPlaying)
//                            
//                            Button(action: {
//                            }) {
//                                Label("Go forward", systemImage: "\(String(format: "%.0f", player.forwardInterval)).arrow.trianglehead.clockwise")
//                            }
//                            .disabled(!player.isPlaying)
//                            .labelStyle(.iconOnly)
//                        }
//                        .opacity(0)
//                        
//                        Image("peapod-mark")
//                            .resizable()
//                            .frame(width:29, height:22)
//                    }
//                }
//                .padding(.leading, 16)
//                .frame(maxWidth:.infinity, alignment:.leading)
//            }
        }
        .frame(maxWidth:.infinity)
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
