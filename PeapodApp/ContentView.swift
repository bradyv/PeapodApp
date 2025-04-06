//
//  ContentView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import CoreData
import Kingfisher

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var selectedEpisode: Episode? = nil
    
    var body: some View {
        ZStack {
            ScrollView {
                QueueView()
                LibraryView()
                SubscriptionsView()
            }
            .onAppear {
                EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
                }
            }
            .refreshable {
                EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
            }
            
            if let episode = player.currentEpisode {
                VStack {
                    Spacer()
                    HStack(spacing:16) {
                        Button(action: {
                            player.skipBackward(seconds:15)
                            print("Seeking back")
                        }) {
                            Label("Go back", systemImage: "15.arrow.trianglehead.counterclockwise")
                        }
                        .disabled(!player.isPlayingEpisode(episode))
                        .labelStyle(IconOnlyLabelStyle())
                        
                        Button(action: {
                            player.stop()
                            player.markAsPlayed(for: episode)
                            try? episode.managedObjectContext?.save()
                        }) {
                            Label("Mark as played", systemImage:"checkmark.circle")
                        }
                        .labelStyle(IconOnlyLabelStyle())
                        
                        KFImage(URL(string:episode.podcast?.image ?? ""))
                            .resizable()
                            .frame(width: 24, height: 24)
                            .cornerRadius(3)
                            .if(player.isPlayingEpisode(episode),
                                transform: {
                                $0.shadow(color:
                                            (Color(hex: episode.episodeTint))
                                            ?? (Color(hex: episode.podcast?.podcastTint))
                                            ?? Color.black.opacity(0.35),
                                            radius: 8
                            )})
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                        
                        Button(action: {
                            player.togglePlayback(for: episode)
                            print("Playing episode")
                        }) {
                            Label(player.isPlayingEpisode(episode) ? "Pause" : "Play", systemImage:player.isPlayingEpisode(episode) ? "pause.fill" :  "play.fill")
                        }
                        .labelStyle(IconOnlyLabelStyle())
                        
                        Button(action: {
                            player.skipForward(seconds: 30)
                            print("Going forward")
                        }) {
                            Label("Go forward", systemImage: "30.arrow.trianglehead.clockwise")
                        }
                        .disabled(!player.isPlayingEpisode(episode))
                        .labelStyle(IconOnlyLabelStyle())
                    }
                    .padding(.horizontal,12).padding(.vertical,8)
                    .background(.ultraThickMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                        .inset(by: 1)
                        .stroke(Color.surface.opacity(0.5), lineWidth: 1)
                    )
                    .overlay(
                        Capsule()
                        .inset(by: 0.5)
                        .stroke(Color.background, lineWidth: 1)
                    )
                    
                }
                .sheet(item: $selectedEpisode) { episode in
                    EpisodeView(episode: episode)
                        .modifier(PPSheet())
                }
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()
