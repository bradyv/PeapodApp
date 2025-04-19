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
    @ObservedObject var episode: Episode
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var parsedDescription: NSAttributedString?
    
    var body: some View {
        ZStack(alignment:.topLeading) {
            VStack {
                FadeInView(delay: 0.1) {
                    KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                        .resizable()
                        .aspectRatio(1, contentMode:.fit)
                        .mask(
                            LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.85))
                        )
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
                                .padding(.horizontal)
                            
                            Text(parseHtmlToAttributedString(episode.episodeDescription ?? "", linkColor: Color.tint(for:episode, darkened: true)))
                                .multilineTextAlignment(.leading)
                            
//                            Text(parseHtml(episode.episodeDescription ?? ""))
//                                .foregroundStyle(.white.opacity(0.75))
//                                .multilineTextAlignment(.leading)
//                                .textBody()
                        }
                        .offset(y:-64)
                        .padding(.horizontal)
                    }
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
                VStack {
                    HStack {
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
