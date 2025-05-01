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
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var selectedPodcast: Podcast? = nil
    @State private var isPlaying = false
    var displayedInQueue: Bool = false
    var displayedFullscreen: Bool = false
    var savedView: Bool = false
    var namespace: Namespace.ID
    
    var body: some View {
        VStack(alignment:.leading) {
            // Podcast Info Row
            HStack {
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
                    HStack {
                        KFImage(URL(string:episode.podcast?.image ?? ""))
                            .resizable()
                            .frame(width: 24, height: 24)
                            .cornerRadius(3)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.15), lineWidth: 1))
                            .matchedTransitionSource(id: episode.id, in: namespace)
                        
                        Text(episode.podcast?.title ?? "Podcast title")
                            .lineLimit(1)
                            .foregroundStyle(displayedInQueue ? Color.white : Color.heading)
                            .textDetailEmphasis()
                    }
                }
                
                Text(getRelativeDateString(from: episode.airDate ?? Date.distantPast))
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
                                    .multilineTextAlignment(.leading)
                                    .titleCondensed()
                                    .lineLimit(4)
                                    .layoutPriority(2)
                                
                                Text(parseHtml(episode.episodeDescription ?? "Episode description", flat: true))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .multilineTextAlignment(.leading)
                                    .textBody()
                            }
                            .frame(maxWidth:.infinity, alignment: .leading)
                            .background(Color.clear)
                        }
                }
            } else {
                // Body
                VStack(alignment:.leading, spacing:8) {
                    Text(episode.title ?? "Episode title")
                        .foregroundStyle(Color.heading)
                        .multilineTextAlignment(.leading)
                        .if(displayedFullscreen,
                            transform: { $0.titleSerif() },
                            else: { $0.titleCondensed() }
                        )
                    
                    Text(parseHtml(episode.episodeDescription ?? "Episode description", flat: displayedFullscreen ? false : true))
                        .foregroundStyle(Color.text)
                        .multilineTextAlignment(.leading)
                        .textBody()
                }
                .frame(maxWidth:.infinity, alignment: .leading)
            }
            
            // Episode Actions
            if displayedInQueue {
                HStack {
                    Button(action: {
                        player.togglePlayback(for: episode)
                    }) {
                        HStack {
                            if player.isPlayingEpisode(episode) {
                                if player.isLoadingEpisode(episode) {
                                    PPSpinner(color: Color.black)
                                } else {
                                    WaveformView(isPlaying: $isPlaying, color: .black)
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
                            
                            if player.isPlayingEpisode(episode) || player.getProgress(for: episode) > 0 {
                                let isQQ = displayedInQueue
                                let safeDuration: Double = {
                                    let actual = episode.actualDuration
                                    return actual > 1 ? actual : episode.duration
                                }()
                                
                                CustomSlider(
                                    value: Binding(
                                        get: { player.getProgress(for: episode) },
                                        set: { player.seek(to: $0) }
                                    ),
                                    range: 0...safeDuration,
                                    onEditingChanged: { isEditing in
                                        if !isEditing {
                                            player.seek(to: player.progress)
                                        }
                                    },
                                    isDraggable: false,
                                    isQQ: isQQ
                                )
                                .frame(width: 32)
                            }
                            
                            Text(player.getStableRemainingTime(for: episode))
                        }
                    }
                    .buttonStyle(
                        PPButton(
                            type: .filled,
                            colorStyle: .monochrome,
                            hierarchical: false,
                            customColors: ButtonCustomColors(
                                foreground: .black,
                                background: .white
                            )
                        )
                    )
                    
                    if displayedInQueue {
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
                            if player.isPlayingEpisode(episode) || player.hasStartedPlayback(for: episode) {
                                Label("Mark as played", systemImage: "checkmark.circle")
                            } else {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                        .buttonStyle(
                            PPButton(
                                type: .transparent,
                                colorStyle: .monochrome,
                                iconOnly: true,
                                customColors: ButtonCustomColors(
                                    foreground: .white,
                                    background: .white.opacity(0.15)
                                )
                            )
                        )
                    }
                }
            } else {
                HStack {
                    Button(action: {
                        player.togglePlayback(for: episode)
                    }) {
                        HStack {
                            if player.isPlayingEpisode(episode) {
                                if player.isLoadingEpisode(episode) {
                                    PPSpinner(color: Color.background)
                                } else {
                                    WaveformView(isPlaying: $isPlaying, color: Color.background)
                                }
                            } else {
                                Image(systemName: episode.isPlayed ? "arrow.clockwise" : "play.circle.fill")
                                
                            }
                            
                            if player.isPlayingEpisode(episode) || player.getProgress(for: episode) > 0 {
                                let isQQ = displayedInQueue
                                let safeDuration: Double = {
                                    let actual = episode.actualDuration
                                    return actual > 1 ? actual : episode.duration
                                }()
                                
                                CustomSlider(
                                    value: Binding(
                                        get: { player.getProgress(for: episode) },
                                        set: { player.seek(to: $0) }
                                    ),
                                    range: 0...safeDuration,
                                    onEditingChanged: { isEditing in
                                        if !isEditing {
                                            player.seek(to: player.progress)
                                        }
                                    },
                                    isDraggable: false,
                                    isQQ: isQQ
                                )
                                .frame(width: 32)
                            }
                            
                            Text(player.getStableRemainingTime(for: episode))
                        }
                    }
                    .buttonStyle(
                        PPButton(
                            type: .filled,
                            colorStyle: .monochrome,
                            hierarchical: false
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
                        Label(episode.isQueued ? "Queued" : "Up Next", systemImage: episode.isQueued ? "text.badge.checkmark" : "text.append")
                    }
                    .buttonStyle(
                        episode.isQueued
                        ? PPButton(
                            type: .transparent,
                            colorStyle: .tinted,
                            iconOnly: true
                        )
                        : PPButton(
                            type: .transparent,
                            colorStyle: .monochrome
                        )
                    )
                    .id(episode.isQueued ? "queued" : "unqueued")
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: episode.isQueued)
                    
                    if savedView {
                        Spacer()
                        
                        Button(action: {
                            episode.isSaved.toggle()
                            try? episode.managedObjectContext?.save()
                        }) {
                            Label(episode.isSaved ? "Remove from saved" : "Save episode", systemImage: episode.isSaved ? "bookmark.slash" : "bookmark")
                        }
                        .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
                        .sensoryFeedback(episode.isSaved ? .success : .warning, trigger: episode.isSaved)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth:.infinity, alignment: .leading)
        .onAppear {
            Task.detached(priority: .background) {
                await player.writeActualDuration(for: episode)
                await ColorTintManager.applyTintIfNeeded(to: episode, in: context)
            }
        }
        .onReceive(player.$isPlaying) { newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPlaying = newValue && player.currentEpisode?.id == episode.id
                }
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
