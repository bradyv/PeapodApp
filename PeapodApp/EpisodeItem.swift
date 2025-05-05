//
//  EpisodeItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI

struct EpisodeItem: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var episodeSelectionManager: EpisodeSelectionManager
    @ObservedObject var episode: Episode
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var selectedPodcast: Podcast? = nil
    @State private var isPlaying = false
    var displayedInQueue: Bool = false
    var displayedFullscreen: Bool = false
    var savedView: Bool = false
    var namespace: Namespace.ID
    
    func updateView() {
        // Force UI update when episode state changes
        if player.isPlayingEpisode(episode) {
            isPlaying = true
        } else {
            isPlaying = false
        }
    }
    
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
                        ArtworkView(url:episode.podcast?.image ?? "", size: 24, cornerRadius: 4)
                        
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
                        if episode.isPlayed && !player.isPlayingEpisode(episode) {
                            // Need to reset the played state first to ensure proper queueing
                            episode.isPlayed = false
                            try? episode.managedObjectContext?.save()
                        }
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
                                let safeDuration = player.getActualDuration(for: episode)
                                
                                PPProgress(
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
                    
                    if player.isPlayingEpisode(episode) || player.hasStartedPlayback(for: episode) || episode.playbackPosition > 0 {
                        
                        // nothing
                    } else {
                        Button(action: {
                            withAnimation {
                                toggleQueued(episode)
                                toggleSaved(episode)
                            }
                            try? episode.managedObjectContext?.save()
                        }) {
                            Label("Later", systemImage: "bookmark")
                        }
                        .buttonStyle(
                            PPButton(
                                type:.transparent,
                                colorStyle:.monochrome,
                                customColors: ButtonCustomColors(
                                    foreground: .white,
                                    background: .white.opacity(0.15)
                                )
                            )
                        )
                    }
                    
                    if displayedInQueue {
                        Button(action: {
                            if player.isPlayingEpisode(episode) || player.hasStartedPlayback(for: episode) {
                                withAnimation {
                                    player.stop()
                                    player.markAsPlayed(for: episode, manually: true)
                                }
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
                        if episode.isPlayed && !player.isPlayingEpisode(episode) {
                            // Need to reset the played state first to ensure proper queueing
                            episode.isPlayed = false
                            try? episode.managedObjectContext?.save()
                        }
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
                                let safeDuration = player.getActualDuration(for: episode)
                                
                                PPProgress(
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
                            withAnimation {
                                toggleSaved(episode)
                            }
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
            
            // Ensure UI state is correct when view appears
            isPlaying = player.isPlayingEpisode(episode)
        }
        .onChange(of: episode.isPlayed) { oldValue, newValue in
            // Force UI update when episode played state changes
            updateView()
        }
        .onReceive(player.$isPlaying) { newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPlaying = newValue && player.currentEpisode?.id == episode.id
                }
            }
        }
        .onTapGesture {
            episodeSelectionManager.selectEpisode(episode)
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
