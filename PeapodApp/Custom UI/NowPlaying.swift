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
    var episodeID: String?
    @State private var displayedEpisode: Episode?
    
    var body: some View {
        ZStack {
            if let id = episodeID,
               let episode = displayedEpisode {
                KFImage(URL(string: episode.episodeImage ?? episode.podcast?.image ?? ""))
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .blur(radius: 64)
                    .opacity(0.35)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .ignoresSafeArea(.all)
                    .transition(.opacity)
                    .id(episode.id) // Forces view identity change to animate transition
                    .animation(.easeInOut(duration: 0.3), value: episode.id)
            }
        }
        .onChange(of: episodeID) { newID in
            if let id = newID {
                if let match = nowPlaying.first(where: { $0.id == id }) {
                    withAnimation {
                        displayedEpisode = match
                    }
                }
            }
        }
    }
}

struct NowPlaying: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var selectedEpisode: Episode? = nil
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.queuePosition)],
        predicate: NSPredicate(format: "nowPlaying == YES"),
        animation: .interactiveSpring()
    )
    var nowPlaying: FetchedResults<Episode>
    var displayedInQueue: Bool = false
    
    var body: some View {
        
        if let episode = nowPlaying.first {
            VStack(alignment:.center) {
                Spacer()
                
                HStack {
                    HStack(spacing:2) {
                        Button(action: {
                            withAnimation {
                                player.togglePlayback(for: episode)
                            }
                            print("Playing episode")
                        }) {
                            if player.isPlayingEpisode(episode) {
                                if player.isLoadingEpisode(episode) {
                                    PPSpinner(color: Color.background)
                                } else {
                                    Image(systemName: "pause")
                                }
                            } else {
                                Image(systemName: "play.fill")
                            }
                        }
                        .buttonStyle(PPButton(
                            type: .transparent,
                            colorStyle: .monochrome,
                            iconOnly: true,
                            customColors: ButtonCustomColors(
                                foreground: .background,
                                background: .heading
                            )))
                        
                        Button(action: {
                            player.skipBackward(seconds:15)
                            print("Seeking back")
                        }) {
                            Label("Go back", systemImage: "15.arrow.trianglehead.counterclockwise")
                        }
                        .disabled(!player.isPlayingEpisode(episode))
                        .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true, customColors:ButtonCustomColors(foreground: player.isPlayingEpisode(episode) ? .heading : .heading.opacity(0.15), background: .clear)))
                        
                        Button(action: {
                            player.skipForward(seconds:30)
                            print("Seeking back")
                        }) {
                            Label("Go back", systemImage: "30.arrow.trianglehead.clockwise")
                        }
                        .disabled(!player.isPlayingEpisode(episode))
                        .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true, customColors:ButtonCustomColors(foreground: player.isPlayingEpisode(episode) ? .heading : .heading.opacity(0.15), background: .clear)))
                    }
                    .padding(2)
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
                    
                    VStack {
                        KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                            .resizable()
                            .frame(width:36,height:36)
                            .clipShape(Circle())
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.3), value: player.isPlaying)
                    }
                    .padding(2)
                    .background(.thinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .inset(by: 1)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .inset(by: 0.5)
                            .stroke(Color.black.opacity(0.15), lineWidth: 1)
                    )
                    .onTapGesture {
                        selectedEpisode = episode
                    }
                }
                .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 3)
            }
            .padding(8)
            .sheet(item: $selectedEpisode) { episode in
                EpisodeView(episode: episode)
                    .modifier(PPSheet(showOverlay: false))
            }
            .frame(maxWidth:.infinity)
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
