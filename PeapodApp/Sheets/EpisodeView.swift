//
//  EpisodeView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher
import Pow
import TipKit

struct EpisodeView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    @State private var selectedPodcast: Podcast? = nil
    @State private var scrollOffset: CGFloat = 0
    @State private var favoriteCount = 0
    var skipTip = SkipTip()
    
    // Computed properties based on unified state
    private var isPlaying: Bool {
        player.isPlayingEpisode(episode)
    }
    
    private var isLoading: Bool {
        player.isLoadingEpisode(episode)
    }
    
    var body: some View {
        
        ScrollView {
            Color.clear
                .frame(height: 1)
                .trackScrollOffset("scroll") { value in
                    scrollOffset = value
                }
            
            FadeInView(delay: 0.1) {
                ArtworkView(url: episode.episodeImage ?? episode.podcast?.image ?? "", size: 256, cornerRadius: 32, tilt: true)
            }
            
            Spacer().frame(height:24)
            
            FadeInView(delay: 0.2) {
                VStack(spacing: 8) {
                    Text(episode.title ?? "Episode title")
                        .titleSerif()
                        .multilineTextAlignment(.center)
                    
                    HStack {
                        HStack {
                            ArtworkView(url: episode.podcast?.image ?? "", size: 24, cornerRadius: 6)
                            
                            Text(episode.podcast?.title ?? "Podcast title")
                                .lineLimit(1)
                                .textDetailEmphasis()
                        }
                        .onTapGesture {
                            selectedPodcast = episode.podcast
                        }
                        .sheet(item: $selectedPodcast) { podcast in
                            PodcastDetailView(feedUrl: episode.podcast?.feedUrl ?? "")
                                .modifier(PPSheet())
                        }
                        
                        Text(getRelativeDateString(from: episode.airDate ?? Date.distantPast))
                            .textDetail()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    Spacer().frame(height: 8)
                    
                    HStack {
                        let hasStarted = isPlaying || player.hasStartedPlayback(for: episode) || episode.playbackPosition > 0
                        
                        if !hasStarted {
                            Button(action: {
                                if episode.isQueued {
                                    withAnimation {
                                        removeFromQueue(episode)
                                    }
                                } else {
                                    withAnimation {
                                        toggleQueued(episode)
                                    }
                                }
                            }) {
                                Label(episode.isQueued ? "Archive" : "Up Next", systemImage: episode.isQueued ? "archivebox" : "text.append")
                            }
                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome))
                        }
                        
                        Button(action: {
                            withAnimation {
                                player.markAsPlayed(for: episode, manually: true)
                            }
                        }) {
                            Label(episode.isPlayed ? "Mark as Unplayed" : "Mark as Played", systemImage: episode.isPlayed ? "circle.dashed" : "checkmark.circle")
                        }
                        .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome))
                        
                        Button(action: {
                            withAnimation {
                                let wasFavorite = episode.isFav
                                toggleFav(episode)
                                
                                // Only increment counter when favoriting (not unfavoriting)
                                if !wasFavorite && episode.isFav {
                                    favoriteCount += 1
                                }
                            }
                        }) {
                            Label("Favorite", systemImage: episode.isFav ? "heart.fill" : "heart")
                        }
                        .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
                        .changeEffect(
                            .spray(origin: UnitPoint(x: 0.25, y: 0.5)) {
                              Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            }, value: favoriteCount)
                    }
                    
                    Spacer().frame(height: 8)
                    
                    HStack(spacing: 16) {
                        Text(player.getElapsedTime(for: episode))
                            .fontDesign(.monospaced)
                            .font(.caption)
                            .onTapGesture {
                                player.skipBackward(seconds: player.backwardInterval)
                            }
                        
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
                        .disabled(!player.isPlayingEpisode(episode))
                        
                        Text("-\(player.getStableRemainingTime(for: episode, pretty: false))")
                            .fontDesign(.monospaced)
                            .font(.caption)
                            .onTapGesture {
                                player.skipForward(seconds: player.forwardInterval)
                            }
                            .if(player.isPlaying, transform: { $0.popoverTip(skipTip, arrowEdge: .bottom) })
                    }
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
            }
            
            Spacer().frame(height: 24)
            
            FadeInView(delay: 0.3) {
                Text("Episode notes")
                    .titleSerifMini()
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .padding(.horizontal)
                
                Spacer().frame(height:8)
                
                Text(parseHtmlToAttributedString(episode.episodeDescription ?? ""))
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .multilineTextAlignment(.leading)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "peapod", url.host == "seek",
                           let query = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           let seconds = query.queryItems?.first(where: { $0.name == "t" })?.value,
                           let time = Double(seconds) {
                            
                            player.seek(to: time)
                            return .handled
                        }
                        
                        return .systemAction
                    })
            }
        }
        .background {
            SplashImage(image: episode.episodeImage ?? episode.podcast?.image ?? "")
                .offset(y:-200)
        }
        .background(Color.background)
        .coordinateSpace(name: "scroll")
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        player.togglePlayback(for: episode)
                    }
                }) {
                    Group {
                        HStack {
                            if isLoading {
                                PPSpinner(color: Color.white)
                                    .transition(.scale.combined(with: .opacity))
                            } else if isPlaying {
                                Image(systemName: "pause.fill")
                                    .foregroundStyle(Color.white)
                                    .textBody()
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "play.fill")
                                    .foregroundStyle(Color.white)
                                    .textBody()
                                    .transition(.scale.combined(with: .opacity))
                            }
                            
                            Text(isPlaying ? "Pause" : "Listen Now")
                                .foregroundStyle(.white)
                                .textBodyEmphasis()
                        }
                        .padding(.horizontal,8)
                    }
                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                    .animation(.easeInOut(duration: 0.2), value: isPlaying)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .task {
            // Configure and load your tips at app launch.
            do {
                try Tips.configure()
            }
            catch {
                // Handle TipKit errors
                print("Error initializing TipKit \(error.localizedDescription)")
            }
        }
    }
}

struct SkipTip: Tip {
    var title: Text {
        Text("Jump Around")
    }
    
    var message: Text? {
        Text("Tap the timestamps to skip forward or backward.")
    }
}
