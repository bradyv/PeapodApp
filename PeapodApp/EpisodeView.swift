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
    var namespace: Namespace.ID
    
    var body: some View {
        ZStack(alignment:.topLeading) {
            SplashImage(image: episode.episodeImage ?? episode.podcast?.image ?? "")
            
            VStack {
                ScrollView {
                    Color.clear
                        .frame(height: 1)
                        .trackScrollOffset("scroll") { value in
                            scrollOffset = value
                        }
                    Spacer().frame(height:128)
                    VStack {
                        FadeInView(delay: 0.2) {
                            VStack(alignment:.leading, spacing:8) {
                                HStack(spacing: 2) {
                                    Text("Released ")
                                        .textDetail()
                                    Text(getRelativeDateString(from: episode.airDate ?? .distantPast))
                                        .textDetailEmphasis()
                                }
                                .frame(maxWidth:.infinity,alignment:.leading)
                                
                                Text(episode.title ?? "Episode title")
                                    .titleSerifSm()
                                    .multilineTextAlignment(.leading)
                                
                                Spacer().frame(height:24)
                            }
                            .padding(.horizontal)
                            .frame(maxWidth:.infinity, alignment:.leading)
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
                            VStack(spacing:16) {
                                if episode.isQueued {
                                    VStack(spacing:2) {
                                        let safeDuration = episode.actualDuration > 0 ? episode.actualDuration : episode.duration
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
                                
                                HStack {
                                    if episode.isQueued {
                                        Group {
                                            AirPlayButton()
                                                .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
                                            
                                            Spacer()
                                            
                                            HStack(spacing: player.isPlayingEpisode(episode) ? -4 : -22) {
                                                Button(action: {
                                                    player.skipBackward(seconds:15)
                                                    print("Seeking back")
                                                }) {
                                                    Label("Go back", systemImage: "15.arrow.trianglehead.counterclockwise")
                                                }
                                                .disabled(!player.isPlayingEpisode(episode))
                                                .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true, customColors:ButtonCustomColors(foreground: player.isPlayingEpisode(episode) ? .heading : .heading.opacity(0), background: .surface)))
                                                
                                                VStack {
                                                    Button(action: {
                                                        player.togglePlayback(for: episode)
                                                        print("Playing episode")
                                                    }) {
                                                        Label(player.isPlayingEpisode(episode) ? "Pause" : "Play", systemImage:player.isPlayingEpisode(episode) ? "pause.fill" :  "play.fill")
                                                            .font(.title)
                                                    }
                                                    .buttonStyle(PPButton(type:.filled,colorStyle:.monochrome,iconOnly: true,large: true))
                                                }
                                                .overlay(Circle().stroke(Color.background, lineWidth:5))
                                                .zIndex(1)
                                                
                                                Button(action: {
                                                    player.skipForward(seconds: 30)
                                                    print("Going forward")
                                                }) {
                                                    Label("Go forward", systemImage: "30.arrow.trianglehead.clockwise")
                                                }
                                                .disabled(!player.isPlayingEpisode(episode))
                                                .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true, customColors:ButtonCustomColors(foreground: player.isPlayingEpisode(episode) ? .heading : .heading.opacity(0), background: .surface)))
                                            }
                                            .animation(.easeInOut(duration: 0.25), value: player.isPlayingEpisode(episode))
                                        }
                                        .transition(.opacity)
                                    } else {
                                        Group {
                                            Button(action: {
                                                withAnimation {
                                                    player.togglePlayback(for: episode)
                                                }
                                            }) {
                                                Label("Listen Now", systemImage: "play.fill")
                                                    .frame(maxWidth:.infinity)
                                            }
                                            .buttonStyle(PPButton(type:.filled, colorStyle:.monochrome))
                                            
                                            Button(action: {
                                                withAnimation {
                                                    toggleQueued(episode)
                                                }
                                                try? episode.managedObjectContext?.save()
                                            }) {
                                                Label("Up Next", systemImage: "text.append")
                                            }
                                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome))
                                        }
                                        .transition(
                                            .asymmetric(
                                                insertion: .scale(scale: 1, anchor: .center).combined(with: .opacity),
                                                removal: .scale(scale: 0, anchor: .center).combined(with: .opacity)
                                            )
                                        )
                                    }
                                    Spacer()
                                    Button(action: {
                                        episode.isSaved.toggle()
                                        try? episode.managedObjectContext?.save()
                                    }) {
                                        Label(episode.isSaved ? "Remove from starred" : "Save episode", systemImage: episode.isSaved ? "bookmark.fill" : "bookmark")
                                    }
                                    .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true, customColors: ButtonCustomColors(foreground: episode.isSaved ? .background : .heading, background: episode.isSaved ? .yellow : .surface)))
                                    .sensoryFeedback(episode.isSaved ? .success : .warning, trigger: episode.isSaved)
                                }
                                .animation(.easeOut(duration: 0.3), value: episode.isQueued)
                            }
                            .padding(.horizontal).padding(.bottom)
                        }
                        .background(Color.background)
                    }
                }
            }
            
            FadeInView(delay: 0.1) {
                VStack(alignment:.leading) {
                    let minSize: CGFloat = 64
                    let maxSize: CGFloat = 172
                    let threshold: CGFloat = 72
                    let shrink = max(minSize, min(maxSize, maxSize + min(0, scrollOffset - threshold)))
                    
                    Spacer().frame(height:16)
                    KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                        .resizable()
                        .frame(width: shrink, height: shrink)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25), lineWidth: 1))
                        .animation(.easeOut(duration: 0.1), value: shrink)
                    Spacer()
                }
                .frame(maxWidth:.infinity, alignment:.leading)
                .padding(.horizontal)
            }
        }
        .frame(maxWidth:.infinity)
        .onAppear {
            nowPlayingManager.isVisible = false
        }
        .onDisappear {
            nowPlayingManager.isVisible = true
        }
    }
}
