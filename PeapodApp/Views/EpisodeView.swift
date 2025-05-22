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
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedPodcast: Podcast? = nil
    @State private var currentForwardInterval: Double = AudioPlayerManager.shared.forwardInterval
    @State private var currentBackwardInterval: Double = AudioPlayerManager.shared.backwardInterval
    @State private var showSpeeds = false
    @State private var speedPopover: Bool = false
    @State private var isPlaying = false
    @State private var isLoading = false
    var namespace: Namespace.ID
    
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
                    
//                    FadeInView(delay: 0.1) {
//                        KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
//                            .resizable()
//                            .frame(width:128,height:128)
//                            .clipShape(RoundedRectangle(cornerRadius:16))
//                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25), lineWidth: 1))
//                        
//                        Spacer().frame(
//                    }
                    
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
                                if episode.isQueued {
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
                                if episode.isQueued {
                                    
                                    Group {
                                        HStack(spacing:16) {
                                            AirPlayButton()
                                            
                                            Spacer()
                                            
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
                                            
                                            Spacer()
                                            
                                            EpisodeContextMenu(episode: episode, displayedFullscreen: true, displayedInQueue: false, namespace: namespace)
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
                                                    toggleQueued(episode)
                                                }
                                            }) {
                                                Label("Up Next", systemImage: "text.append")
                                            }
                                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome))
                                            
                                            EpisodeContextMenu(episode: episode, displayedFullscreen: true, displayedInQueue: false, namespace: namespace)
                                        }
                                    }
                                    .transition(.opacity)
                                }
                            }
                            .padding(.horizontal).padding(.bottom)
                        }
                        .background(Color.background)
                    }
                }
            }
            .padding(.top)
            
//            FadeInView(delay: 0.1) {
//                VStack(alignment:.leading) {
//                    let minSize: CGFloat = 64
//                    let maxSize: CGFloat = 172
//                    let threshold: CGFloat = 72
//                    let shrink = max(minSize, min(maxSize, maxSize + min(0, scrollOffset - threshold)))
//                    
//                    KFImage(URL(string:episode.podcast?.image ?? ""))
//                        .resizable()
//                        .frame(width: shrink, height: shrink)
//                        .clipShape(RoundedRectangle(cornerRadius: 16))
//                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25), lineWidth: 1))
//                        .animation(.easeOut(duration: 0.1), value: shrink)
//                    
//                    Spacer()
//                }
//                .frame(maxWidth:.infinity, alignment:.leading)
//                .padding()
//            }
        }
        .frame(maxWidth:.infinity)
        .onAppear {
            isPlaying = player.isPlayingEpisode(episode)
            isLoading = player.isLoadingEpisode(episode)
        }
        .onChange(of: player.state) { newState in
            withAnimation(.easeInOut(duration: 0.3)) {
                isPlaying = player.isPlayingEpisode(episode)
                isLoading = player.isLoadingEpisode(episode)
            }
        }
    }
}
