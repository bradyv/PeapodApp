//
//  EpisodeView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct EpisodeView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var nowPlayingManager: NowPlayingVisibilityManager
    @ObservedObject var episode: Episode
    @ObservedObject var player = AudioPlayerManager.shared
    @ObservedObject private var queueManager = QueueManager.shared
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedPodcast: Podcast? = nil
    @State private var currentSpeed: Float = AudioPlayerManager.shared.playbackSpeed
    @State private var currentForwardInterval: Double = AudioPlayerManager.shared.forwardInterval
    @State private var currentBackwardInterval: Double = AudioPlayerManager.shared.backwardInterval
    @State private var showSpeeds = false
    @State private var speedPopover: Bool = false
    @State private var isPlaying = false
    @State private var isLoading = false
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
        ZStack(alignment:.topTrailing) {
            let splashFadeStart: CGFloat = -150
            let splashFadeEnd: CGFloat = 0
            let clamped = min(max(scrollOffset, splashFadeStart), splashFadeEnd)
            let opacity = (clamped - splashFadeStart) / (splashFadeEnd - splashFadeStart) + 0.15
            
            FadeInView(delay: 0.1) {
                KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                    .resizable()
                    .aspectRatio(1, contentMode:.fit)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                       startPoint: .top, endPoint: .init(x:0.5,y:0.8))
                    )
                    .opacity(opacity)
            }
            
            VStack {
                ScrollView {
                    Color.clear
                        .frame(height: 1)
                        .trackScrollOffset("scroll") { value in
                            scrollOffset = value
                        }
                    Spacer().frame(height:256)
                    
                    VStack {
                        FadeInView(delay: 0.2) {
                            VStack(spacing:8) {
                                HStack(spacing: 2) {
                                    Text("Released ")
                                        .textDetail()
                                    Text(getRelativeDateString(from: episode.airDate ?? .distantPast))
                                        .textDetailEmphasis()
                                }
                                .frame(maxWidth:.infinity)
                                
                                Text(episode.title ?? "Episode title")
                                    .titleSerifSm()
                                    .multilineTextAlignment(.center)
                                
                                Spacer().frame(height:24)
                            }
                            .padding(.horizontal)
                            .frame(maxWidth:.infinity)
                        }
                        
                        FadeInView(delay: 0.3) {
                            Text(parseHtmlToAttributedString(episode.episodeDescription ?? ""))
                                .padding(.horizontal)
                                .multilineTextAlignment(.leading)
                                .environment(\.openURL, OpenURLAction { url in
                                    if url.scheme == "peapod", url.host == "seek",
                                       let query = URLComponents(url: url, resolvingAgainstBaseURL: false),
                                       let seconds = query.queryItems?.first(where: { $0.name == "t" })?.value,
                                       let time = Double(seconds) {
                                        
                                        AudioPlayerManager.shared.seek(to: time)
                                        return .handled
                                    }
                                    
                                    return .systemAction
                                })
                        }
                    }
                    
                    Spacer().frame(height:32)
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "scroll")
                .maskEdge(.top)
                .maskEdge(.bottom)
                
                FadeInView(delay: 0) {
                    VStack {
                        VStack(spacing:16) {
                            VStack(spacing:0) {
                                if queueManager.contains(episode) {
                                    VStack(spacing:2) {
                                        PPProgress(
                                            value: Binding(
                                                get: { player.getProgress(for: episode) },
                                                set: { player.seek(to: $0) }
                                            ),
                                            range: 0...player.getActualDuration(for: episode),
                                            onEditingChanged: { _ in },
                                            isDraggable: true,
                                            isQQ: false
                                        )
                                        
                                        HStack {
                                            Text(player.getElapsedTime(for: episode))
                                            Spacer()
                                            Text("-\(player.getStableRemainingTime(for: episode, pretty: false))")
                                        }
                                        .fontDesign(.monospaced)
                                        .font(.caption)
                                    }
                                }
                                
                                // new actions
                                if queueManager.contains(episode) {
                                    
                                    Group {
                                        HStack(spacing:16) {
                                            AirPlayButton()
                                            
                                            HStack(spacing: player.isPlayingEpisode(episode) ? -4 : -22) {
                                                Button(action: {
                                                    player.skipBackward(seconds:currentBackwardInterval)
                                                }) {
                                                    Label("Go back", systemImage: "\(String(format: "%.0f", currentBackwardInterval)).arrow.trianglehead.counterclockwise")
                                                }
                                                .disabled(!isPlaying)
                                                .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true))
                                                
                                                VStack {
                                                    Button(action: {
                                                        withAnimation {
                                                            player.togglePlayback(for: episode)
                                                        }
                                                    }) {
                                                        if isLoading {
                                                            PPSpinner(color: Color.background)
                                                        } else {
                                                            Label(isPlaying ? "Pause" : "Play",
                                                                  systemImage: isPlaying ? "pause.fill" : "play.fill")
                                                                .font(.title)
                                                        }
                                                    }
                                                    .buttonStyle(PPButton(type:.filled, colorStyle:.monochrome, iconOnly: true, large: true))
                                                }
                                                .overlay(Circle().stroke(Color.background, lineWidth:5))
                                                .zIndex(1)
                                                
                                                Button(action: {
                                                    player.skipForward(seconds: currentForwardInterval)
                                                }) {
                                                    Label("Go forward", systemImage: "\(String(format: "%.0f", currentForwardInterval)).arrow.trianglehead.clockwise")
                                                }
                                                .disabled(!isPlaying)
                                                .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true))
                                            }
                                            .animation(.easeInOut(duration: 0.25), value: player.isPlayingEpisode(episode))
                                            
                                            Button(action: {
                                                toggleFavorite(episode)
                                            }) {
                                                Label(episode.isFav ? "Remove from Favorites" : "Favorite", systemImage: episode.isFav ? "heart.fill" : "heart")
                                                    .if(episode.isFav, transform: {
                                                        $0.foregroundStyle(Color.accentColor)
                                                    })
                                            }
                                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true, borderless: true))
                                            .sensoryFeedback(episode.isFav ? .success : .warning, trigger: episode.isFav)
                                            .contentTransition(.symbolEffect(.replace))
                                            
                                        }
                                    }
                                    .transition(.opacity)
                                } else {
                                    Group {
                                        HStack {
                                            Button(action: {
                                                withAnimation {
                                                    player.togglePlayback(for: episode)
                                                }
                                            }) {
                                                Label(episode.isPlayed ? "Play Again" : "Listen Now", systemImage:episode.isPlayed ? "arrow.clockwise" : "play.fill")
                                                    .frame(maxWidth:.infinity)
                                            }
                                            .buttonStyle(PPButton(type:.filled, colorStyle:.monochrome))
                                            
                                            Button(action: {
                                                withAnimation {
                                                    queueManager.toggle(episode)
                                                }
                                            }) {
                                                Label("Up Next", systemImage: "text.append")
                                            }
                                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome))
                                            
                                            Button(action: {
                                                toggleSaved(episode)
                                            }) {
                                                Label(episode.isSaved ? "Remove from Play Later" : "Play Later", systemImage: "arrowshape.bounce.right")
                                            }
                                            .buttonStyle(PPButton(type:episode.isSaved ? .filled : .transparent, colorStyle:episode.isSaved ? .tinted : .monochrome, iconOnly: true))
                                            .sensoryFeedback(episode.isSaved ? .success : .warning, trigger: episode.isSaved)
                                        }
                                    }
                                    .transition(
                                        .asymmetric(
                                            insertion: .scale(scale: 1, anchor: .center).combined(with: .opacity),
                                            removal: .scale(scale: 0, anchor: .center).combined(with: .opacity)
                                        )
                                    )
                                }
                            }
                            .padding(.horizontal).padding(.bottom)
                        }
                        .background(Color.background)
                    }
                }
            }
            VStack {
                Menu {
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
                        .shadow(color: currentSpeed != 1.0 ? Color.accentColor.opacity(0.5) : Color.clear, radius: 8)
                    }
                    .onReceive(player.$playbackSpeed) { newSpeed in
                        currentSpeed = newSpeed
                    }
                    
                    Button(action: {
                        togglePlayedState(episode)
                    }) {
                        Label(episode.isPlayed ? "Mark as Unplayed" : "Mark as Played", systemImage:episode.isPlayed ? "circle.badge.minus" : "checkmark.circle")
                    }
                    
                    if episode.playbackPosition < 0.1 {
                        Button(action: {
                            withAnimation {
                                queueManager.toggle(episode)
                            }
                        }) {
                            Label(queueManager.contains(episode) ? "Remove from Up Next" : "Add to Up Next", systemImage: queueManager.contains(episode) ? "archivebox" : "text.append")
                        }
                    }
                    
                    Button(action: {
                        toggleSaved(episode)
                    }) {
                        Label(episode.isSaved ? "Remove from Play Later" : "Play Later", systemImage: episode.isSaved ? "minus.circle" : "arrowshape.bounce.right")
                    }
                    
                    Button(action: {
                        toggleFavorite(episode)
                    }) {
                        Label(episode.isFav ? "Remove from Favorites" : "Add to Favorites", systemImage: episode.isFav ? "heart.slash" : "heart")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
            }
            .padding(.top).padding(.trailing)
        }
        .frame(maxWidth:.infinity)
        .onAppear {
            isPlaying = player.isPlayingEpisode(episode)
            isLoading = player.isLoadingEpisode(episode)
        }
        .onChange(of: player.state) { _, newState in
            withAnimation(.easeInOut(duration: 0.3)) {
                isPlaying = player.isPlayingEpisode(episode)
                isLoading = player.isLoadingEpisode(episode)
            }
        }
    }
    
    // MARK: - Helper functions to handle async operations
    
    private func toggleSaved(_ episode: Episode) {
        withAnimation {
            // Start the async operation without awaiting it directly inside withAnimation
            Task {
                await EpisodeStateManager.shared.toggleSaved(episode)
            }
        }
    }
    
    private func toggleFavorite(_ episode: Episode) {
        withAnimation {
            // Start the async operation without awaiting it directly inside withAnimation
            Task {
                await EpisodeStateManager.shared.toggleFav(episode)
            }
        }
    }
    
    private func togglePlayedState(_ episode: Episode) {
        withAnimation {
            Task {
                player.markAsPlayed(for: episode, manually: true)
            }
        }
    }
}
