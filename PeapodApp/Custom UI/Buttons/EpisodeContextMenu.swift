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
    @State private var currentSpeed: Float = AudioPlayerManager.shared.playbackSpeed
    var displayedFullscreen: Bool = false
    var displayedInQueue: Bool = false
    var namespace: Namespace.ID
    
    @ViewBuilder
    func speedButton(for speed: Float) -> some View {
        Button {
            player.setPlaybackSpeed(speed)
        } label: {
            HStack {
                if speed == currentSpeed {
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
                    episodeSelectionManager.selectEpisode(episode)
                }) {
                    Label("Go to Episode", systemImage: "info.square")
                }
            } else {
                Menu {
                    let speeds: [Float] = [2.0, 1.5, 1.2, 1.1, 1.0, 0.75]
                    ForEach(speeds, id: \.self) { speed in
                        speedButton(for: speed)
                    }
                } label: {
                    Label("Playback Speed", systemImage:
                        currentSpeed < 0.5 ? "gauge.with.dots.needle.0percent" :
                        currentSpeed < 0.9 ? "gauge.with.dots.needle.33percent" :
                        currentSpeed > 1.2 ? "gauge.with.dots.needle.100percent" :
                        currentSpeed > 1.0 ? "gauge.with.dots.needle.67percent" :
                        "gauge.with.dots.needle.50percent"
                    )
                }
                .onReceive(player.$playbackSpeed) { newSpeed in
                    currentSpeed = newSpeed
                }
            }
            
            Divider()
            
            Button(action: {
                withAnimation {
                    player.markAsPlayed(for: episode, manually: true)
                }
            }) {
                Label(episode.isPlayed ? "Mark as Unplayed" : "Mark as Played", systemImage:episode.isPlayed ? "circle.badge.minus" : "checkmark.circle")
            }
            
            Button(action: {
                withAnimation {
                    toggleQueued(episode)
                }
            }) {
                Label(episode.isQueued ? "Remove from Up Next" : "Add to Up Next", systemImage: episode.isQueued ? "archivebox" : "text.append")
            }
            
            Button(action: {
                withAnimation {
                    toggleSaved(episode)
                }
            }) {
                Label(episode.isSaved ? "Remove from Play Later" : "Play Later", systemImage: "arrowshape.bounce.right")
            }
            
            Button(action: {
                withAnimation {
                    toggleFav(episode)
                }
            }) {
                Label(episode.isFav ? "Remove from Favorites" : "Add to Favorites", systemImage: episode.isFav ? "heart.slash" : "heart")
            }
            
            if !displayedFullscreen {
                Divider()
                
                NavigationLink {
                    if episode.podcast?.isSubscribed != false {
                        PPPopover(hex: episode.podcast?.podcastTint ?? "#FFFFFF") {
                            PodcastDetailView(feedUrl: episode.podcast?.feedUrl ?? "", namespace: namespace)
                        }
                    } else {
                        PPPopover(hex: episode.podcast?.podcastTint ?? "#FFFFFF") {
                            PodcastDetailLoaderView(feedUrl: episode.podcast?.feedUrl ?? "", namespace: namespace)
                        }
                    }
                } label: {
                    Label("Go to Show", systemImage: "widget.large")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .frame(width:24,height:24)
        }
        .buttonStyle(PPButton(
            type:.transparent,
            colorStyle: .monochrome,
            iconOnly: true,
            customColors: displayedInQueue ?
            ButtonCustomColors(foreground: .white, background: .white.opacity(0.15)) :
                nil
            )
        )
        .menuOrder(.fixed)
    }
}
