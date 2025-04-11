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
    
    var body: some View {
        ZStack(alignment:.topLeading) {
            VStack {
                FadeInView(delay: 0.3) {
                    ScrollView {
                        Spacer().frame(height:76)
                        EpisodeItem(episode: episode, displayedFullscreen:true)
                            .padding(.horizontal)
                        
                        Spacer().frame(height:64)
                    }
                    .maskEdge(.top)
                    .maskEdge(.bottom)
                    .padding(.top,88)
                }
                
                FadeInView(delay: 0.4) {
                    VStack {
                        VStack(spacing:16) {
                            VStack(spacing:16) {
                                VStack(spacing:2) {
                                    CustomSlider(
                                        value: Binding<Double>(
                                            get: { player.getProgress(for: episode) },
                                            set: { newValue in player.seek(to: newValue) }
                                        ),
                                        range: 0...episode.duration,
                                        onEditingChanged: { isEditing in
                                            if !isEditing {
                                                player.seek(to: player.progress)
                                            }
                                        },
                                        isDraggable: true, isQQ: false
                                    )
                                    
                                    HStack {
                                        Text(player.getElapsedTime(for: episode))
                                        Spacer()
                                        Text("-\(player.getRemainingTime(for: episode))")
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
                                                .labelStyle(.iconOnly)
                                                .foregroundStyle(Color.heading)
                                                
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
                                            .padding(.vertical).padding(.horizontal,18)
                                            .background(Color.surface)
                                            .clipShape(Capsule())
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                episode.isSaved.toggle()
                                                try? episode.managedObjectContext?.save()
                                            }) {
                                                Label(episode.isSaved ? "Remove from starred" : "Star episode", systemImage: episode.isSaved ? "star.fill" : "star")
                                            }
                                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
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
                                            .buttonStyle(PPButton(type:.filled, colorStyle:.monochrome))
                                            
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
                                Label(episode.isSaved ? "Remove from starred" : "Star episode", systemImage: episode.isSaved ? "star.fill" : "star")
                            }
                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
                            .sensoryFeedback(episode.isSaved ? .success : .warning, trigger: episode.isSaved)
                        }
                    }
                }
                .padding()
            }
            
            VStack {
                FadeInView(delay: 0.1) {
                    KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                        .resizable()
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                        .shadow(color:Color.tint(for:episode),
                                radius: 128
                        )
                }
                
                Spacer()
            }
            .padding()
        }
        .frame(maxWidth:.infinity)
    }
}


