//
//  EpisodeView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher
import TipKit

struct EpisodeView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @ObservedObject var episode: Episode
    
    private var player: AudioPlayerManager { AudioPlayerManager.shared }
    
    @ObservedObject private var timePublisher = AudioPlayerManager.shared.timePublisher
    
    @State private var scrollOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var availableWidth: CGFloat = UIScreen.main.bounds.width - 32
    var skipTip = SkipTip()
    
    // Computed properties based on unified state
    private var isPlaying: Bool {
        player.isPlayingEpisode(episode)
    }
    
    private var isLoading: Bool {
        player.isLoadingEpisode(episode)
    }
    
    private var hasStarted: Bool {
        isPlaying || player.hasStartedPlayback(for: episode) || episode.playbackPosition > 0
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
                VStack(alignment:.center,spacing: 8) {
                    
                    HStack {
                        Text(episode.airDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                            .textDetail()
                        
                        if episode.isQueued {
                            Text("•")
                                .textDetailEmphasis()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled")
                                    .foregroundStyle(Color.heading)
                                    .textDetail()
                                
                                Text("Up Next")
                                    .textDetail()
                            }
                        } else if episode.isPlayed {
                            Text("•")
                                .textDetailEmphasis()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color.heading)
                                    .textDetail()
                                
                                Text("Played")
                                    .textDetail()
                            }
                        }
                        
                        if episode.isFav {
                            Text("•")
                                .textDetailEmphasis()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.orange)
                                    .textDetail()
                                
                                Text("Favorite")
                                    .textDetail()
                            }
                        }
                    }
                    
                    Text(episode.title ?? "Episode title")
                        .titleSerifSm()
                        .multilineTextAlignment(.center)
                    
//                    PodcastDetailsRow(episode: episode)
                    
                    Spacer().frame(height: 8)
                    
                    EpisodeProgressBar
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
                    .frame(maxWidth: availableWidth)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    availableWidth = geo.size.width
                                }
                                .onChange(of: geo.size.width) { _, newWidth in
                                    availableWidth = newWidth
                                }
                        }
                    )
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
            
            Spacer().frame(height: 24)
        }
        .coordinateSpace(name: "scroll")
        .navigationTitle(episode.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .background {
            SplashImage(image: episode.episodeImage ?? episode.podcast?.image ?? "")
                .offset(y:-200)
        }
        .background(Color.background)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement:.principal) {
                Text(scrollOffset < -250 ? "\(episode.title ?? "") " : " ")
                    .font(.system(.headline, design: .serif))
            }
            
            ToolbarItem(placement:.topBarTrailing) {
                FavButton(episode:episode)
            }
            
            ToolbarItemGroup(placement: .bottomBar) {
                // 🔥 FIX: Wrap menu in its own view to isolate from timePublisher updates
                ContextMenuButton(episode: episode)
                
                Spacer()
                
                // Play button needs to update, so it stays here
                PlayButton(episode: episode, isPlaying: isPlaying, isLoading: isLoading, hasStarted: hasStarted)
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
    
    @ViewBuilder
    var EpisodeProgressBar: some View {
        HStack(spacing: 16) {
            Text(player.getElapsedTime(for: episode))
                .fontDesign(.monospaced)
                .font(.caption)
                .onTapGesture {
                    player.skipBackward()
                }
            
            PPProgress(
                value: Binding(
                    get: {
                        player.getProgress(for: episode)
                    },
                    set: { newValue in
                        player.seek(to: newValue)
                    }
                ),
                range: 0...player.getActualDuration(for: episode),
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        player.updateNowPlayingInfo()
                    }
                },
                isDraggable: true,
                isQQ: false
            )
            .disabled(!player.isPlayingEpisode(episode))
            
            Text("-\(player.getStableRemainingTime(for: episode, pretty: false))")
                .fontDesign(.monospaced)
                .font(.caption)
                .onTapGesture {
                    player.skipForward()
                }
                .if(player.isPlaying, transform: { $0.popoverTip(skipTip, arrowEdge: .bottom) })
        }
    }
}

// 🔥 NEW: Separate view for context menu button to prevent flashing
struct ContextMenuButton: View {
    let episode: Episode
    
    var body: some View {
        Menu {
            ArchiveButton(episode: episode)
            MarkAsPlayedButton(episode: episode)
            FavButton(episode: episode)
            DownloadActionButton(episode: episode)
            
            Section(episode.podcast?.title ?? "") {
                NavigationLink {
                    PodcastDetailView(feedUrl: episode.podcast?.feedUrl ?? "")
                } label: {
                    Label("View Podcast", systemImage: "widget.small")
                }
            }
        } label: {
            Label("More", systemImage:"ellipsis")
                .frame(width:34,height:34)
        }
        .menuOrder(.fixed)
        .labelStyle(.iconOnly)
    }
}

// 🔥 NEW: Separate view for play button that needs live updates
struct PlayButton: View {
    let episode: Episode
    let isPlaying: Bool
    let isLoading: Bool
    let hasStarted: Bool
    
    private var player: AudioPlayerManager { AudioPlayerManager.shared }
    
    var body: some View {
        Button(action: {
            player.togglePlayback(for: episode)
        }) {
            Group {
                HStack {
                    if isLoading {
                        PPSpinner(color: Color.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(Color.white)
                            .textBody()
                            .transition(.scale.combined(with: .opacity))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    
                    Text(isPlaying ? "Pause" : (hasStarted ? "Resume" : (episode.isPlayed ? "Listen Again" : "Listen")))
                        .foregroundStyle(.white)
                        .textBodyEmphasis()
                        .contentTransition(.interpolate)
                }
                .padding(.horizontal,8)
            }
            .animation(.easeInOut(duration: 0.2), value: isLoading)
            .animation(.easeInOut(duration: 0.2), value: isPlaying)
        }
        .buttonStyle(.glassProminent)
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
