//
//  EpisodeItem.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Pow

struct EpisodeItem: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @State private var workItem: DispatchWorkItem?
    @State private var favoriteCount = 0
    @Namespace private var namespace
    
    // Computed properties based on unified state
    private var isPlaying: Bool {
        player.isPlayingEpisode(episode)
    }
    
    private var isLoading: Bool {
        player.isLoadingEpisode(episode)
    }
    
    private var playbackPosition: Double {
        player.getProgress(for: episode)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Podcast Info Row
            HStack {
                HStack {
                    ZStack(alignment:.bottomTrailing) {
                        ArtworkView(url: episode.podcast?.image ?? "", size: 24, cornerRadius: 6)
                            .matchedTransitionSource(id: episode.id, in: namespace)
                        
                        if episode.isPlayed {
                            ZStack {
                                Image(systemName:"checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .textMini()
                            }
                            .background(Color.background)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.background, lineWidth: 1)
                            )
                            .offset(x:5)
                        }
                    }
                    
                    Text(episode.podcast?.title ?? "Podcast title")
                        .lineLimit(1)
                        .foregroundStyle(Color.white)
                        .textDetailEmphasis()
                }
                
                Text(getRelativeDateString(from: episode.airDate ?? Date.distantPast))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .textDetail()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Episode Meta
            VStack(alignment: .leading) {
                Text("Line\nLine\nLine\nLine")
                    .titleCondensed()
                    .lineLimit(4, reservesSpace: true)
                    .frame(maxWidth: .infinity)
                    .hidden()
                    .overlay(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.clear)
                    }
            }
            
            // Episode Actions
            HStack {
                let hasStarted = isPlaying || player.hasStartedPlayback(for: episode) || player.getProgress(for: episode) > 0.1
                // ▶️ Playback Button
                Button(action: {
                    guard !isLoading else { return }
                    player.togglePlayback(for: episode)
                }) {
                    HStack {
                        PPCircularPlayButton(
                            episode: episode,
                            displayedInQueue: true,
                            buttonSize: 20
                        )
                        
                        Text("\(player.getStableRemainingTime(for: episode, pretty: true))")
                            .contentTransition(.numericText())
                            .foregroundStyle(Color.white)
                            .textButton()
                    }
                }
                .buttonStyle(.bordered)
                .tint(.white)
                
                if hasStarted {
                    Button(action: {
                        withAnimation {
                            removeFromQueue(episode, episodesViewModel: episodesViewModel)
                            player.markAsPlayed(for: episode, manually: true)
                        }
                    }) {
                        Label("Mark as Played", systemImage: "checkmark.circle")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(Color.white)
                            .textButton()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                } else {
                    Button(action: {
                        withAnimation {
                            removeFromQueue(episode, episodesViewModel: episodesViewModel)
                        }
                    }) {
                        Label("Archive", systemImage: "archivebox")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(Color.white)
                            .textButton()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        let wasFavorite = episode.isFav
                        toggleFav(episode, episodesViewModel: episodesViewModel)
                        
                        // Only increment counter when favoriting (not unfavoriting)
                        if !wasFavorite && episode.isFav {
                            favoriteCount += 1
                        }
                    }
                }) {
                    Label("Favorite", systemImage: episode.isFav ? "heart.fill" : "heart")
                        .foregroundStyle(Color.white)
                        .textButton()
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .labelStyle(.iconOnly)
                .changeEffect(
                    .spray(origin: UnitPoint(x: 0.25, y: 0.5)) {
                      Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    }, value: favoriteCount)
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            // Cancel any previous work item
            workItem?.cancel()
            // Create a new work item
            let item = DispatchWorkItem {
                Task.detached(priority: .background) {
                    await player.writeActualDuration(for: episode)
                }
            }
            workItem = item
            // Schedule after 0.5 seconds (adjust as needed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
        }
        .onDisappear {
            // Cancel if the user scrolls away before debounce interval
            workItem?.cancel()
        }
    }
}

struct EmptyEpisodeItem: View {
    var body: some View {
        VStack {
            HStack {
                Rectangle()
                    .frame(width: 24, height: 24)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            VStack(alignment: .leading) {
                Rectangle()
                    .frame(maxWidth: .infinity).frame(height: 24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width: 100, height: 24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            VStack(alignment: .leading) {
                Rectangle()
                    .frame(maxWidth: .infinity).frame(height: 12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(maxWidth: .infinity).frame(height: 12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width: 128, height: 12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.bottom, 16)
            
            HStack {
                Capsule()
                    .frame(width: 96, height: 40)
                    .foregroundStyle(Color.heading)
                
                Capsule()
                    .frame(width: 128, height: 40)
                    .foregroundStyle(Color.heading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .padding(.bottom, 24)
    }
}
