//
//  EpisodeContextMenu.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-21.
//

import SwiftUI

struct EpisodeContextMenu: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var episodeSelectionManager: EpisodeSelectionManager
    @ObservedObject var episode: Episode
    @ObservedObject var player = AudioPlayerManager.shared
    @ObservedObject var userManager = UserManager.shared
    @State private var selectedEpisode: Episode? = nil
    @State private var selectedPodcast: Podcast? = nil
    @State private var showingUpgrade = false
    var displayedFullscreen: Bool = false
    var displayedInQueue: Bool = false
    var namespace: Namespace.ID
    
    @ViewBuilder
    func speedButton(for speed: Float) -> some View {
        Button {
            player.playbackSpeed = speed  // Direct assignment now triggers didSet
        } label: {
            HStack {
                if speed == player.playbackSpeed {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.heading)
                }
                
                Text("\(speed, specifier: "%.1fx")")
                    .foregroundStyle(Color.heading)
            }
        }
    }
    
    var body: some View {
        Menu {
            if !displayedFullscreen {
                Button(action: {
                    selectedEpisode = episode
//                    episodeSelectionManager.selectEpisode(episode)
                }) {
                    Label("Go to Episode", systemImage: "info.square")
                }
            } else {
                if userManager.isSubscriber {
                    Menu {
                        let speeds: [Float] = [2.0, 1.5, 1.2, 1.1, 1.0, 0.75]
                        ForEach(speeds, id: \.self) { speed in
                            speedButton(for: speed)
                        }
                    } label: {
                        Label("Playback Speed", systemImage:
                                player.playbackSpeed < 0.5 ? "gauge.with.dots.needle.0percent" :
                                player.playbackSpeed < 0.9 ? "gauge.with.dots.needle.33percent" :
                                player.playbackSpeed > 1.2 ? "gauge.with.dots.needle.100percent" :
                                player.playbackSpeed > 1.0 ? "gauge.with.dots.needle.67percent" :
                                "gauge.with.dots.needle.50percent"
                        )
                    }
                } else {
                    Button(action: {
                        showingUpgrade = true
                    }) {
                        Label("Playback Speed",
                              systemImage: "gauge.with.dots.needle.50percent")
                    }
                }
            }
            
            Divider()
            
            Button(action: {
                withAnimation {
                    player.markAsPlayed(for: episode, manually: true)
                }
            }) {
                Label(episode.isPlayed ? "Mark as Unplayed" : "Mark as Played",
                      systemImage: episode.isPlayed ? "circle.badge.minus" : "checkmark.circle")
            }
            
            Button(action: {
                withAnimation {
                    if episode.isQueued {
                        removeFromQueue(episode)
                    } else {
                        toggleQueued(episode)
                    }
                }
            }) {
                Label(episode.isQueued ? "Remove from Up Next" : "Add to Up Next",
                      systemImage: episode.isQueued ? "archivebox" : "text.append")
            }
            
            Button(action: {
                withAnimation {
                    toggleSaved(episode)
                }
            }) {
                Label(episode.isSaved ? "Remove from Play Later" : "Play Later",
                      systemImage: "arrowshape.bounce.right")
            }
            
            Button(action: {
                withAnimation {
                    toggleFav(episode)
                }
            }) {
                Label(episode.isFav ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: episode.isFav ? "heart.slash" : "heart")
            }
            
//            if !displayedFullscreen {
                Divider()
                
                Button {
                    selectedPodcast = episode.podcast
//                    if episode.podcast?.isSubscribed != false {
//                        PPPopover(hex: episode.podcast?.podcastTint ?? "#FFFFFF") {
//                            PodcastDetailView(feedUrl: episode.podcast?.feedUrl ?? "", namespace: namespace)
//                        }
//                    } else {
//                        PPPopover(hex: episode.podcast?.podcastTint ?? "#FFFFFF") {
//                            PodcastDetailLoaderView(feedUrl: episode.podcast?.feedUrl ?? "", namespace: namespace)
//                        }
//                    }
                } label: {
                    Label("Go to Show", systemImage: "widget.large")
                }
//            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(PPButton(
            type: .transparent,
            colorStyle: .monochrome,
            iconOnly: true,
            customColors: displayedInQueue ?
            ButtonCustomColors(foreground: .white, background: .white.opacity(0.15)) :
                nil
            )
        )
        .menuOrder(.fixed)
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode, namespace:namespace)
                .modifier(PPSheet())
        }
        .sheet(item: $selectedPodcast) { podcast in
            if podcast.isSubscribed {
                PodcastDetailView(feedUrl: episode.podcast?.feedUrl ?? "", namespace: namespace)
                    .modifier(PPSheet())
            } else {
                PodcastDetailLoaderView(feedUrl: episode.podcast?.feedUrl ?? "", namespace:namespace)
                    .modifier(PPSheet())
            }
        }
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView()
                .modifier(PPSheet())
        }
    }
}
