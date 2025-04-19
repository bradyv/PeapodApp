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
    @ObservedObject var episode: Episode
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var parsedDescription: NSAttributedString?
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment:.topLeading) {
            VStack {
                let fadeStart: CGFloat = 0
                let fadeEnd: CGFloat = 300
                let clamped = min(max(scrollOffset, fadeStart), fadeEnd)
                let opacity = 0 + (clamped - fadeStart) / (fadeEnd - fadeStart)
                
                FadeInView(delay: 0.1) {
                    KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                        .resizable()
                        .aspectRatio(1, contentMode:.fit)
                        .mask(
                            LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.85))
                        )
                        .opacity(opacity)
                        .animation(.easeOut(duration: 0.1), value: opacity)
                }
                
                Spacer()
            }
            
            VStack {
                FadeInView(delay: 0.3) {
                    ScrollView {
                        KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                            .resizable()
                            .aspectRatio(1, contentMode:.fit)
                            .opacity(0)
                            
                        VStack(spacing:24) {
                            
                            Text(episode.title ?? "Episode title")
                                .titleSerif()
                                .multilineTextAlignment(.center)
                                .trackScrollOffset("scroll") { value in
                                    scrollOffset = value
                                }
                            
                            Text(parseHtmlToAttributedString(episode.episodeDescription ?? "", linkColor: Color.tint(for:episode, darkened: colorScheme == .dark ? false : true)))
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
                            
//                            Text(parseHtml(episode.episodeDescription ?? ""))
//                                .foregroundStyle(.white.opacity(0.75))
//                                .multilineTextAlignment(.leading)
//                                .textBody()
                        }
                        .offset(y:-64)
                    }
                    .contentMargins(16, for: .scrollContent)
                    .coordinateSpace(name: "scroll")
                    .maskEdge(.top)
                    .maskEdge(.bottom)
                }
                
                FadeInView(delay: 0.4) {
                    VStack {
                        VStack(spacing:16) {
                            VStack(spacing:16) {
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
                                
                                HStack {
                                    HStack {
                                        if episode.isQueued {
                                            AirPlayButton()
                                                .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
                                            
                                            Spacer()
                                            
                                            HStack(spacing:16) {
                                                Button(action: {
                                                    player.skipBackward(seconds:15)
                                                    print("Seeking back")
                                                }) {
                                                    Label("Go back", systemImage: "15.arrow.trianglehead.counterclockwise")
                                                }
                                                .disabled(!player.isPlayingEpisode(episode))
                                                .labelStyle(.iconOnly)
                                                .foregroundStyle(player.isPlayingEpisode(episode) ? Color.heading : Color.heading.opacity(0.5))
                                                
                                                Button(action: {
                                                    player.togglePlayback(for: episode)
                                                    print("Playing episode")
                                                }) {
                                                    Label(player.isPlayingEpisode(episode) ? "Pause" : "Play", systemImage:player.isPlayingEpisode(episode) ? "pause.fill" :  "play.fill")
                                                        .font(.title)
                                                }
                                                .buttonStyle(PPButton(
                                                    type:.transparent,
                                                    colorStyle:.monochrome,
                                                    iconOnly: true,
                                                    large: true,
                                                    customColors: ButtonCustomColors(
                                                        foreground: .white,
                                                        background: Color.tint(for:episode, darkened: true)
                                                        )
                                                    )
                                                )
//                                                .labelStyle(.iconOnly)
//                                                .foregroundStyle(Color.heading)
                                                
                                                Button(action: {
                                                    player.skipForward(seconds: 30)
                                                    print("Going forward")
                                                }) {
                                                    Label("Go forward", systemImage: "30.arrow.trianglehead.clockwise")
                                                }
                                                .disabled(!player.isPlayingEpisode(episode))
                                                .labelStyle(.iconOnly)
                                                .foregroundStyle(player.isPlayingEpisode(episode) ? Color.heading : Color.heading.opacity(0.5))
                                            }
//                                            .padding(.vertical).padding(.horizontal,18)
//                                            .background(Color.surface)
//                                            .clipShape(Capsule())
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                episode.isSaved.toggle()
                                                try? episode.managedObjectContext?.save()
                                            }) {
                                                Label(episode.isSaved ? "Remove from starred" : "Save episode", systemImage: episode.isSaved ? "bookmark.fill" : "bookmark")
                                            }
                                            .buttonStyle(PPButton(type:episode.isSaved ? .filled : .transparent, colorStyle:episode.isSaved ? .tinted : .monochrome, iconOnly: true))
                                            .sensoryFeedback(episode.isSaved ? .success : .warning, trigger: episode.isSaved)
                                            
                                        } else {
                                            Button(action: {
                                                withAnimation {
                                                    player.togglePlayback(for: episode)
                                                }
                                            }) {
                                                Label("Listen Now", systemImage: "play.fill")
                                                    .frame(maxWidth:.infinity)
                                            }
                                            .buttonStyle(PPButton(type:.filled, colorStyle:.monochrome, customColors: ButtonCustomColors(foreground: .white, background: Color.tint(for:episode, darkened: true))))
                                            
                                            Button(action: {
                                                withAnimation {
                                                    toggleQueued(episode)
                                                }
                                                try? episode.managedObjectContext?.save()
                                            }) {
                                                Label("Up Next", systemImage: "plus.circle")
                                            }
                                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome))
                                        }
                                    }
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(.easeOut(duration: 0.3), value: episode.isQueued)

                                }
                            }
                            .padding(.horizontal).padding(.bottom)
                        }
                        .background(Color.background)
                    }
                }
            }
            
            FadeInView(delay: 0.5) {
                let fadeStart: CGFloat = 0
                let fadeEnd: CGFloat = 300
                let clamped = min(max(scrollOffset, fadeStart), fadeEnd)
                let opacity = 1 - (clamped - fadeStart) / (fadeEnd - fadeStart)
                
                VStack {
                    HStack {
                        KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1))
                            .shadow(color:Color.tint(for:episode),
                                    radius: 32
                            )
                            .opacity(opacity)
                            .animation(.easeOut(duration: 0.1), value: opacity)
                        
                        Spacer()
                        
                        if episode.isQueued {
                            Button(action: {
                                withAnimation {
                                    toggleQueued(episode)
                                }
                                try? episode.managedObjectContext?.save()
                            }) {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
                        } else {
                            Button(action: {
                                episode.isSaved.toggle()
                                try? episode.managedObjectContext?.save()
                            }) {
                                Label(episode.isSaved ? "Remove from saved" : "Save episode", systemImage: episode.isSaved ? "bookmark.fill" : "bookmark")
                            }
                            .buttonStyle(PPButton(type:episode.isSaved ? .filled : .transparent, colorStyle:episode.isSaved ? .tinted : .monochrome, iconOnly: true))
                            .sensoryFeedback(episode.isSaved ? .success : .warning, trigger: episode.isSaved)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth:.infinity)
    }
}
