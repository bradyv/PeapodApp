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
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.15), lineWidth: 1))
                    
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
            if displayedInQueue {
                VStack(alignment: .leading) {
                    
                    Text("Line\nLine\nLine\nLine")
                        .titleCondensed()
                        .lineLimit(4, reservesSpace: true)
                        .frame(maxWidth: .infinity)
                        .hidden()
                        .overlay(alignment:.top) {
                            VStack(alignment: .leading, spacing:4) {
                                Text(episode.title ?? "Episode title")
                                    .foregroundStyle(.white)
                                    .titleCondensed()
                                    .lineLimit(4)
                                    .layoutPriority(2)
                                
                                Text(parseHtmlFlat(episode.episodeDescription ?? "Episode description"))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .multilineTextAlignment(.leading)
                                    .textBody()
                            }
                            .frame(maxWidth:.infinity, alignment: .leading)
                            .background(Color.clear)
                        }
                }
            } else {
                VStack(alignment:.leading, spacing:8) {
                    Text(episode.title ?? "Episode title")
                        .foregroundStyle(Color.heading)
                        .if(displayedFullscreen,
                            transform: { $0.titleSerif() },
                            else: { $0.titleCondensed() }
                        )
                    
                    if displayedFullscreen {
                        Text(parseHtml(episode.episodeDescription ?? "Episode description"))
                            .foregroundStyle(Color.text)
                            .textBody()
                    } else {
                        Text(parseHtmlFlat(episode.episodeDescription ?? "Episode description"))
                            .foregroundStyle(Color.text)
                            .textBody()
                    }
                }
                .frame(maxWidth:.infinity, alignment: .leading)
            }
            
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
                                    .if(player.isPlayingEpisode(episode)) { view in
                                        view.symbolEffect(.variableColor.cumulative.dimInactiveLayers.nonReversing)
                                    }
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
                                
                                CustomSlider(
                                    value: Binding(
                                        get: { player.getProgress(for: episode) },
                                        set: { player.seek(to: $0) }
                                    ),
                                    range: 0...(player.isPlayingEpisode(episode) ? player.duration : episode.duration),
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
                            player.markAsPlayed(for: episode, manually: true)
                            try? episode.managedObjectContext?.save()
                        } else {
                            withAnimation {
                                toggleQueued(episode)
                            }
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
                            Label(episode.isQueued ? "Queued" : "Up Next", systemImage: episode.isQueued ? "checkmark" : "plus.circle")
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
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.3), value: episode.isQueued)
                    
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
                await ColorTintManager.applyTintIfNeeded(to: episode, in: context)
            }
        }
    }
}

struct EmptyEpisodeItem: View {
    var body: some View {
        VStack {
            HStack {
                Rectangle()
                    .frame(width:24, height:24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width: 96, height: 12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width: 32, height: 12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            .padding(.horizontal)
            
            VStack(alignment:.leading) {
                Rectangle()
                    .frame(maxWidth:.infinity).frame(height:24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width:100, height:24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            .padding(.horizontal)
            
            VStack(alignment:.leading) {
                
                Rectangle()
                    .frame(maxWidth:.infinity).frame(height:12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(maxWidth:.infinity).frame(height:12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width:128, height:12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            .padding(.horizontal).padding(.bottom,16)
            
            HStack {
                Capsule()
                    .frame(width:96,height:40)
                    .foregroundStyle(Color.heading)
                
                Capsule()
                    .frame(width:128,height:40)
                    .foregroundStyle(Color.heading)
            }
            .frame(maxWidth:.infinity,alignment:.leading)
            .padding(.horizontal)
        }
        .padding(.bottom,24)
    }
}

#Preview {
    EmptyEpisodeItem()
}
