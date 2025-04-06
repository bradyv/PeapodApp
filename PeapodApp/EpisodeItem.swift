//
//  EpisodeItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct EpisodeItem: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var episode: Episode
    var displayedInQueue: Bool = false
    var displayedFullscreen: Bool = false
    var savedView: Bool = false
    @State private var selectedPodcast: Podcast? = nil
    @ObservedObject var player = AudioPlayerManager.shared
    
    var body: some View {
        VStack(alignment:.leading) {
            // Podcast Info Row
            HStack {
                HStack {
                    KFImage(URL(string:episode.podcast?.image ?? ""))
                        .resizable()
                        .frame(width: 24, height: 24)
                        .cornerRadius(3)
                    
                    Text(episode.podcast?.title ?? "Podcast title")
                        .lineLimit(1)
                        .foregroundStyle(displayedInQueue ? Color.white : Color.heading)
                        .textDetailEmphasis()
                }
                .onTapGesture {
                    selectedPodcast = episode.podcast
                }
                
                Text(episode.airDate ?? Date.distantPast, style: .date)
                    .foregroundStyle(displayedInQueue ? Color.white.opacity(0.75) : Color.text)
                    .textDetail()
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            
            // Episode Meta
            VStack(alignment:.leading, spacing:8) {
                Text(episode.title ?? "Episode title")
                    .foregroundStyle(displayedInQueue ? Color.white : Color.heading)
                    .if(displayedFullscreen,
                        transform: { $0.titleSerif() },
                        else: { $0.titleCondensed() }
                    )
                
                Text(parseHtml(episode.episodeDescription ?? "Episode description"))
                    .foregroundStyle(displayedInQueue ? Color.white.opacity(0.75) : Color.text)
                    .textBody()
            }
            .frame(maxWidth:.infinity, alignment: .leading)
            
            // Episode Actions
            if !displayedFullscreen {
                HStack {
                    Button(action: {
                        player.togglePlayback(for: episode)
                        print("Playing \(episode.title ?? "Episode title")")
                    }) {
                        HStack {
                            if player.isPlayingEpisode(episode) {
                                Image(systemName: "waveform")
                            } else {
                                if episode.isPlayed {
                                    if displayedInQueue {
                                        Image(systemName: "play.circle.fill")
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                } else {
                                    Image(systemName: "play.circle.fill")
                                }
                            }

                            if player.isPlayingEpisode(episode) || player.hasStartedPlayback(for: episode) {
                                let isQQ = displayedInQueue
                                let durationToUse = player.currentEpisode?.id == episode.id && player.duration > 1
                                    ? player.duration
                                    : Double(player.getRemainingTime(for: episode))
                                
                                CustomSlider(
                                    value: Binding(
                                        get: { player.getSavedPlaybackPosition(for: episode) },
                                        set: { player.seek(to: $0) }
                                    ),
                                    range: 0...episode.duration,
                                    onEditingChanged: { isEditing in
                                        if !isEditing {
                                            player.seek(to: player.progress)
                                        }
                                    },
                                    isDraggable: false, isQQ: isQQ
                                )
                                .frame(width: 32)

                                Text(player.getRemainingTimePretty(for: episode))
                            } else {
                                Text(formatDuration(seconds: Int((episode.duration))))
                            }
                        }
                    }
                    .buttonStyle(
                        displayedInQueue
                            ? PPButton(
                                type: .filled,
                                colorStyle: .monochrome,
                                customColors: ButtonCustomColors(
                                    foreground: .black,
                                    background: .white
                                )
                            )
                            : PPButton(
                                type: .filled,
                                colorStyle: .monochrome
                            )
                    )
                    
                    Button(action: {
                        if player.isPlayingEpisode(episode) || player.hasStartedPlayback(for: episode) {
                            player.stop()
                            player.markAsPlayed(for: episode)
                            try? episode.managedObjectContext?.save()
                        } else {
                            episode.isQueued.toggle()
                            try? episode.managedObjectContext?.save()
                        }
                    }) {
                        if displayedInQueue {
                            if player.isPlayingEpisode(episode) || player.hasStartedPlayback(for: episode) {
                                Label("Mark as played", systemImage: "checkmark.circle")
                            } else {
                                Label("Archive", systemImage: "archivebox")
                            }
                        } else {
                            Label(episode.isQueued ? "Queued" : "Add to queue", systemImage: episode.isQueued ? "checkmark" : "plus.circle")
                        }
                    }
                    .buttonStyle(
                        displayedInQueue
                            ? PPButton(
                                type: .transparent,
                                colorStyle: .monochrome,
                                iconOnly: true,
                                customColors: ButtonCustomColors(
                                    foreground: .white,
                                    background: .white.opacity(0.15)
                                )
                            )
                            : episode.isQueued
                                ? PPButton(
                                    type: .filled,
                                    colorStyle: .tinted
                                    )
                                : PPButton(
                                    type: .transparent,
                                    colorStyle: .monochrome
                                )
                    )
                    
                    if savedView {
                        Spacer()
                        
                        Button(action: {
                            episode.isSaved.toggle()
                            try? episode.managedObjectContext?.save()
                        }) {
                            Label("Remove from starred", systemImage: "star.slash")
                        }
                        .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
                    }
                }
            }
        }
        .sheet(item: $selectedPodcast) { podcast in
            PodcastDetailView(feedUrl: podcast.feedUrl ?? "")
                .modifier(PPSheet())
        }
        .frame(maxWidth:.infinity, alignment: .leading)
        .onAppear {
            Task.detached(priority: .background) {
                ColorTintManager.applyTintIfNeeded(to: episode, in: context)
            }
        }
    }
}
