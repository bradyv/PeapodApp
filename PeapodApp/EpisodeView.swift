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
                            Rectangle()
                                .frame(maxWidth:.infinity).frame(height:1)
                                .foregroundStyle(Color.surface)
                            VStack {
                                VStack {
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
                                    AirPlayButton()
                                        .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted, iconOnly: true))
                                    
                                    Spacer()
                                    
                                    HStack {
                                        if episode.isQueued {
                                            Button(action: {
                                                player.skipBackward(seconds:15)
                                                print("Seeking back")
                                            }) {
                                                Label("Go back", systemImage: "15.arrow.trianglehead.counterclockwise")
                                            }
                                            .disabled(!player.isPlayingEpisode(episode))
                                            .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted, iconOnly: true))
                                            
                                            Button(action: {
                                                player.togglePlayback(for: episode)
                                                print("Playing episode")
                                            }) {
                                                Label(player.isPlayingEpisode(episode) ? "Pause" : "Play", systemImage:player.isPlayingEpisode(episode) ? "pause.fill" :  "play.fill")
                                            }
                                            .buttonStyle(PPButton(type:.filled, colorStyle:.tinted, iconOnly: true))
                                            
                                            Button(action: {
                                                player.skipForward(seconds: 30)
                                                print("Going forward")
                                            }) {
                                                Label("Go forward", systemImage: "30.arrow.trianglehead.clockwise")
                                            }
                                            .disabled(!player.isPlayingEpisode(episode))
                                            .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted, iconOnly: true))
                                            
                                        } else {
                                            Button(action: {
                                                withAnimation {
                                                    toggleQueued(episode)
                                                }
                                                try? episode.managedObjectContext?.save()
                                            }) {
                                                Label("Add to queue", systemImage: "plus.circle")
                                            }
                                            .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted))
                                            
                                            Button(action: {
                                                withAnimation {
                                                    player.togglePlayback(for: episode)
                                                }
                                                print("Playing episode")
                                            }) {
                                                Label("Play", systemImage: "play.fill")
                                            }
                                            .buttonStyle(PPButton(type:.filled, colorStyle:.tinted, iconOnly: true))
                                        }
                                    }
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(.easeOut(duration: 0.3), value: episode.isQueued)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        episode.isSaved.toggle()
                                        try? episode.managedObjectContext?.save()
                                    }) {
                                        Label(episode.isSaved ? "Remove from starred" : "Star episode", systemImage: episode.isSaved ? "star.fill" : "star")
                                    }
                                    .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted, iconOnly: true))
                                }
                            }
                            .padding(.horizontal).padding(.bottom)
                        }
                        .background(.ultraThickMaterial)
                    }
                }
            }
            
            if episode.isQueued {
                FadeInView(delay: 0.5) {
                    VStack {
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                episode.isQueued.toggle()
                                try? episode.managedObjectContext?.save()
                            }) {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
            }
            
            VStack {
                FadeInView(delay: 0.1) {
                    KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                        .resizable()
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                        .shadow(color:
                                    (Color(hex: episode.episodeTint)?.opacity(0.5))
                                ?? (Color(hex: episode.podcast?.podcastTint)?.opacity(0.45))
                                ?? Color.black.opacity(0.35),
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
