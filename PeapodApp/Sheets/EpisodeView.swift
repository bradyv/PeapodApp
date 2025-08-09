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
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var nowPlayingManager: NowPlayingVisibilityManager
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    @State private var selectedPodcast: Podcast? = nil
    @State private var scrollOffset: CGFloat = 0
    
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
                            ArtworkView(url: episode.podcast?.image ?? "", size: 24, cornerRadius: 4)
                            
                            Text(episode.podcast?.title ?? "Podcast title")
                                .lineLimit(1)
                                .textDetailEmphasis()
                        }
                        .onTapGesture {
                            selectedPodcast = episode.podcast
                        }
                        .sheet(item: $selectedPodcast) { podcast in
                            if podcast.isSubscribed {
                                PodcastDetailView(feedUrl: episode.podcast?.feedUrl ?? "")
                                    .modifier(PPSheet())
                            } else {
                                PodcastDetailLoaderView(feedUrl: episode.podcast?.feedUrl ?? "")
                                    .modifier(PPSheet())
                            }
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
                                toggleFav(episode)
                            }
                        }) {
                            Label("Favorite", systemImage: episode.isFav ? "heart.fill" : "heart")
                        }
                        .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
                    }
                    
                    Spacer().frame(height: 8)
                    
                    HStack(spacing: 16) {
                        Text(player.getElapsedTime(for: episode))
                            .fontDesign(.monospaced)
                            .font(.caption)
                        
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
        }
        .coordinateSpace(name: "scroll")
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button(action: {
                    player.skipBackward(seconds: player.backwardInterval)
                }) {
                    Label("Go back", systemImage: "\(String(format: "%.0f", player.backwardInterval)).arrow.trianglehead.counterclockwise")
                }
                .disabled(!isPlaying)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        player.togglePlayback(for: episode)
                    }
                }) {
                    Group {
                        if isLoading {
                            PPSpinner(color: Color.white)
                                .transition(.scale.combined(with: .opacity))
                        } else if isPlaying {
                            Image(systemName: "pause.fill")
                                .foregroundStyle(.white)
                                .textBody()
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.white)
                                .textBody()
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                    .animation(.easeInOut(duration: 0.2), value: isPlaying)
                }
                
                Button(action: {
                    player.skipForward(seconds: player.forwardInterval)
                }) {
                    Label("Go forward", systemImage: "\(String(format: "%.0f", player.forwardInterval)).arrow.trianglehead.clockwise")
                }
                .disabled(!isPlaying)
            }
        }
    }
}
