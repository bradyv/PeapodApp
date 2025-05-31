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
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedPodcast: Podcast? = nil
    var namespace: Namespace.ID
    
    // Computed properties based on unified state
    private var isPlaying: Bool {
        player.isPlayingEpisode(episode)
    }
    
    private var isLoading: Bool {
        player.isLoadingEpisode(episode)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            let splashFadeStart: CGFloat = -150
            let splashFadeEnd: CGFloat = 0
            let clamped = min(max(scrollOffset, splashFadeStart), splashFadeEnd)
            let opacity = (clamped - splashFadeStart) / (splashFadeEnd - splashFadeStart) + 0.15
            
            FadeInView(delay: 0.1) {
                KFImage(URL(string: episode.episodeImage ?? episode.podcast?.image ?? ""))
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.8))
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
                    Spacer().frame(height: 256)
                    
                    VStack {
                        FadeInView(delay: 0.2) {
                            VStack(spacing: 8) {
                                HStack(spacing: 2) {
                                    Text("Released ")
                                        .textDetail()
                                    Text(getRelativeDateString(from: episode.airDate ?? .distantPast))
                                        .textDetailEmphasis()
                                }
                                .frame(maxWidth: .infinity)
                                
                                Text(episode.title ?? "Episode title")
                                    .titleSerifSm()
                                    .multilineTextAlignment(.center)
                                
                                Spacer().frame(height: 24)
                            }
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity)
                        }
                        
                        FadeInView(delay: 0.3) {
                            Text(parseHtmlToAttributedString(episode.episodeDescription ?? ""))
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
                    
                    Spacer().frame(height: 32)
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "scroll")
                .maskEdge(.top)
                .maskEdge(.bottom)
                
                FadeInView(delay: 0) {
                    VStack {
                        VStack(spacing: 16) {
                            VStack(spacing: 0) {
                                if episode.isQueued {
                                    VStack(spacing: 2) {
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
                                
                                // Actions for queued episodes
                                if episode.isQueued {
                                    Group {
                                        HStack(spacing: 16) {
                                            AirPlayButton()
                                            
                                            Spacer()
                                            
                                            HStack(spacing: isPlaying ? -4 : -22) {
                                                Button(action: {
                                                    player.skipBackward(seconds: player.backwardInterval)
                                                }) {
                                                    Label("Go back", systemImage: "\(String(format: "%.0f", player.backwardInterval)).arrow.trianglehead.counterclockwise")
                                                }
                                                .disabled(!isPlaying)
                                                .buttonStyle(PPButton(type: .transparent, colorStyle: .monochrome, iconOnly: true))
                                                
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
                                                    .buttonStyle(PPButton(type: .filled, colorStyle: .monochrome, iconOnly: true, large: true))
                                                }
                                                .overlay(Circle().stroke(Color.background, lineWidth: 5))
                                                .zIndex(1)
                                                
                                                Button(action: {
                                                    player.skipForward(seconds: player.forwardInterval)
                                                }) {
                                                    Label("Go forward", systemImage: "\(String(format: "%.0f", player.forwardInterval)).arrow.trianglehead.clockwise")
                                                }
                                                .disabled(!isPlaying)
                                                .buttonStyle(PPButton(type: .transparent, colorStyle: .monochrome, iconOnly: true))
                                            }
                                            .animation(.easeInOut(duration: 0.25), value: isPlaying)
                                            
                                            Spacer()
                                            
                                            EpisodeContextMenu(episode: episode, displayedFullscreen: true, displayedInQueue: false, namespace: namespace)
                                        }
                                    }
                                    .transition(.opacity)
                                } else {
                                    // Actions for non-queued episodes
                                    Group {
                                        HStack {
                                            Button(action: {
                                                withAnimation {
                                                    player.togglePlayback(for: episode)
                                                }
                                            }) {
                                                Label(episode.isPlayed ? "Play Again" : "Listen Now", systemImage: episode.isPlayed ? "arrow.clockwise" : "play.fill")
                                                    .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(PPButton(type: .filled, colorStyle: .monochrome))
                                            
                                            Button(action: {
                                                withAnimation {
                                                    toggleQueued(episode)
                                                }
                                            }) {
                                                Label("Up Next", systemImage: "text.append")
                                            }
                                            .buttonStyle(PPButton(type: .transparent, colorStyle: .monochrome))
                                            
                                            Spacer()
                                            
                                            EpisodeContextMenu(episode: episode, displayedFullscreen: true, displayedInQueue: false, namespace: namespace)
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
        }
        .frame(maxWidth: .infinity)
    }
}
