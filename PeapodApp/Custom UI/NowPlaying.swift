//
//  NowPlaying.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-06.
//

import SwiftUI
import Kingfisher

struct NowPlayingSplash: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.queuePosition)],
        predicate: NSPredicate(format: "isQueued == YES"),
        animation: .interactiveSpring()
    )
    var nowPlaying: FetchedResults<Episode>
    
    var body: some View {
        if let episode = nowPlaying.first {
            KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .blur(radius: 64)
                .opacity(0.5)
                .mask(
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                   startPoint: .top, endPoint: .bottom)
                )
                .ignoresSafeArea(.all)
        }
    }
}

struct NowPlaying: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var selectedEpisode: Episode? = nil
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.queuePosition)],
        predicate: NSPredicate(format: "isQueued == YES"),
        animation: .interactiveSpring()
    )
    var nowPlaying: FetchedResults<Episode>
    
    var body: some View {
        
        if let episode = nowPlaying.first {
            VStack(alignment:.center) {
                Spacer()
                HStack(spacing:4) {
                    Button(action: {
                        player.skipBackward(seconds:15)
                        print("Seeking back")
                    }) {
                        Label("Go back", systemImage: "15.arrow.trianglehead.counterclockwise")
                    }
                    .disabled(!player.isPlayingEpisode(episode))
                    .opacity(player.isPlayingEpisode(episode) ? 1 : 0.5)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: player.isPlaying)
                    .buttonStyle(PPButton(
                        type: .transparent,
                        colorStyle: .monochrome,
                        iconOnly: true,
                        customColors: ButtonCustomColors(
                            foreground: .heading,
                            background: .white.opacity(0)
                        )))
                    
                    Button(action: {
                        player.stop()
                        player.markAsPlayed(for: episode, manually: true)
                    }) {
                        Label("Mark as played", systemImage:"checkmark.circle")
                    }
                    .buttonStyle(PPButton(
                        type: .transparent,
                        colorStyle: .monochrome,
                        iconOnly: true,
                        customColors: ButtonCustomColors(
                            foreground: .heading,
                            background: .white.opacity(0)
                        )))
                    
                    VStack {
                        KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                            .resizable()
                            .frame(width: player.isPlayingEpisode(episode) ? 32 : 24, height: player.isPlayingEpisode(episode) ? 32 : 24)
                            .cornerRadius(player.isPlayingEpisode(episode) ? 6 : 3)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.3), value: player.isPlaying)
                    }
                    .frame(width:32,height:32)
                    Button(action: {
                        withAnimation {
                            player.togglePlayback(for: episode)
                        }
                        print("Playing episode")
                    }) {
                        Label(player.isPlayingEpisode(episode) ? "Pause" : "Play", systemImage:player.isPlayingEpisode(episode) ? "pause.fill" :  "play.fill")
                    }
                    .buttonStyle(PPButton(
                        type: .transparent,
                        colorStyle: .monochrome,
                        iconOnly: true,
                        customColors: ButtonCustomColors(
                            foreground: .heading,
                            background: .white.opacity(0)
                        )))
                    
                    Button(action: {
                        player.skipForward(seconds: 30)
                        print("Going forward")
                    }) {
                        Label("Go forward", systemImage: "30.arrow.trianglehead.clockwise")
                    }
                    .disabled(!player.isPlayingEpisode(episode))
                    .opacity(player.isPlayingEpisode(episode) ? 1 : 0.5)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: player.isPlaying)
                    .buttonStyle(PPButton(
                        type: .transparent,
                        colorStyle: .monochrome,
                        iconOnly: true,
                        customColors: ButtonCustomColors(
                            foreground: .heading,
                            background: .white.opacity(0)
                        )))
                }
                .padding(.horizontal,8).padding(.vertical,4)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .inset(by: 1)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    Capsule()
                        .inset(by: 0.5)
                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                )
                
            }
            .frame(maxWidth:.infinity)
            .sheet(item: $selectedEpisode) { episode in
                EpisodeView(episode: episode)
                    .modifier(PPSheet())
            }
        }
    }
}
//
//struct NowPlayingModifier: ViewModifier {
//
//    func body(content: Content) -> some View {
//        content
//            .overlay(alignment: .bottom) {
//                Group {
//                    NowPlaying()
//                }
//            }
//    }
//}
//
//extension View {
//    func NowPlaying() -> some View {
//        self.modifier(NowPlayingModifier())
//    }
//}
