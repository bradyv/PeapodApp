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
    @ObservedObject var queueManager = QueueManager.shared
    @State private var selectedPodcast: Podcast? = nil
    @State private var isPlaying = false
    @State private var isLoading = false
    @State private var playbackPosition: Double = 0
    @State private var episodePlayed: Bool = false
    var showActions: Bool = false
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
                
                Spacer()
                
                Menu {
                    Button(action: {
                        episodeSelectionManager.selectEpisode(episode)
                    }) {
                        Label("Go to Episode", systemImage: "info.square")
                    }
                    
                    Divider()
                    
                    if !episode.nowPlaying {
                        Button(action: {
                            // Remove withAnimation for instant response
                            player.togglePlayback(for: episode)
                        }) {
                            Label(episode.isPlayed ? "Listen Again" : "Listen Now", systemImage: "play.circle")
                        }
                    }
                    
                    Button(action: {
                        // Remove withAnimation for instant response
                        player.markAsPlayed(for: episode, manually: true)
                    }) {
                        Label(episode.isPlayed ? "Mark as Unplayed" : "Mark as Played", systemImage:episode.isPlayed ? "circle.badge.minus" : "checkmark.circle")
                    }
                    
                    if episode.playbackPosition < 0.1 {
                        Button(action: {
                            // Remove withAnimation for instant response
                            queueManager.toggle(episode)
                        }) {
                            Label(queueManager.contains(episode) ? "Remove from Up Next" : "Add to Up Next", systemImage: queueManager.contains(episode) ? "archivebox" : "text.append")
                        }
                        
                        Button(action: {
                            // Remove withAnimation for instant response
                            toggleSaved(episode)
                        }) {
                            Label(
                                episode.isSaved
                                    ? "Remove from Play Later"
                                    : (episode.playbackPosition > 0.1 ? "Finish Later" : "Play Later"),
                                systemImage: episode.isSaved ? "minus.circle" : "arrowshape.bounce.right"
                            )
                        }
                    }
                    
                    Button(action: {
                        // Remove withAnimation for instant response
                        player.toggleFav(episode)
                    }) {
                        Label(episode.isFav ? "Remove from Favorites" : "Add to Favorites", systemImage: episode.isFav ? "heart.slash" : "heart")
                    }
                    
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
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .frame(width:24,height:24)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(displayedInQueue ? .white : .heading)
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
            if showActions {
                let hasStarted = isPlaying || player.hasStartedPlayback(for: episode) || episode.playbackPosition > 0
                
                HStack {
                    // ▶️ Playback Button
                    Button(action: {
                        guard !isLoading else { return }
                        
                        // Update local state immediately for instant UI feedback
                        if episode.isPlayed && !isPlaying {
                            episodePlayed = false
                        }
                        
                        // Call player without animation wrapper for instant response
                        player.togglePlayback(for: episode)
                    }) {
                        HStack {
                            PPCircularPlayButton(
                                episode: episode,
                                displayedInQueue: displayedInQueue,
                                buttonSize: 20
                            )
                            
                            let duration = episode.actualDuration > 0 ? episode.actualDuration : episode.duration
                            let position = episode.playbackPosition
                            let remaining = max(0, duration - position)
                            let seconds = Int(remaining)
                            
                            Text("\(player.formatDuration(seconds: seconds))")
                                .contentTransition(.numericText())
                        }
                    }
                    .buttonStyle(
                        PPButton(
                            type: .filled,
                            colorStyle: .monochrome,
                            hierarchical: false,
                            customColors: displayedInQueue ?
                            ButtonCustomColors(foreground: .black, background: .white) :
                                nil
                        )
                    )
                    
                    // 📌 "Later" or Queue Toggle
                    if !hasStarted {
                        if displayedInQueue {
                            Button(action: {
                                // Remove withAnimation for instant response
                                toggleSaved(episode)
                            }) {
                                Label("Play Later", systemImage: "arrowshape.bounce.right")
                            }
                            .buttonStyle(
                                PPButton(
                                    type: .transparent,
                                    colorStyle: .monochrome,
                                    customColors: ButtonCustomColors(
                                        foreground: .white,
                                        background: .white.opacity(0.15)
                                    )
                                )
                            )
                            
                            Button(action: {
                                // Remove withAnimation for instant response
                                queueManager.remove(episode)
                            }) {
                                Label("Archive", systemImage: "archivebox")
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
                        } else {
                            Button(action: {
                                // Remove withAnimation for instant response
                                queueManager.toggle(episode)
                            }) {
                                Label(queueManager.contains(episode) ? "Queued" : "Up Next", systemImage: queueManager.contains(episode) ? "text.badge.checkmark" : "text.append")
                            }
                            .buttonStyle(PPButton(type:.transparent, colorStyle: queueManager.contains(episode) ? .tinted : .monochrome))
                        }
                    } else {
                        // 🗑️ Remove / Archive / Mark as Played
                        Button(action: {
                            // Remove withAnimation for instant response
                            player.markAsPlayed(for: episode, manually: true)
                        }) {
                            Label("Mark as Played", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(
                            PPButton(
                                type: .transparent,
                                colorStyle: .monochrome
                            )
                        )
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth:.infinity, alignment: .leading)
        .onAppear {
            // Initialize state from player/episode on appear
            isPlaying = player.isPlayingEpisode(episode)
            isLoading = player.isLoadingEpisode(episode)
            playbackPosition = player.getProgress(for: episode)
            episodePlayed = episode.isPlayed
            
            // Do ALL background tasks without blocking
            Task(priority: .utility) {
                await player.writeActualDuration(for: episode)
            }
            
            Task(priority: .utility) {
                await ColorTintManager.applyTintIfNeeded(to: episode, in: context)
            }
        }
        .onChange(of: player.state) { _, newState in
            // Use explicit animation only for state changes, not for button presses
            withAnimation(.easeInOut(duration: 0.2)) {
                isPlaying = player.isPlayingEpisode(episode)
                isLoading = player.isLoadingEpisode(episode)

                if let id = episode.id, let currentId = newState.currentEpisodeID, id == currentId {
                    playbackPosition = player.getProgress(for: episode)
                }
            }
        }
        // Track changes to episode.isPlayed
        .onChange(of: episode.isPlayed) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                episodePlayed = newValue
                
                // If marked as played, reset progress display
                if newValue {
                    playbackPosition = 0
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
