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
    var displayedInQueue: Bool = false
    
    var body: some View {
        
        if let episode = nowPlaying.first {
            VStack(alignment:.center) {
                Spacer()
                HStack(spacing:8) {
                    HStack {
                        KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                            .resizable()
                            .frame(width:36,height:36)
                            .clipShape(Circle())
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.3), value: player.isPlaying)
                        
                        VStack(alignment:.leading, spacing: 2) {
                            let safeDuration: Double = {
                                let actual = episode.actualDuration
                                return actual > 1 ? actual : episode.duration
                            }()
                            
                            Text(episode.title ?? "Episode title")
                                .textDetailEmphasis()
                                .lineLimit(1)
                            
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
                        }
                        .frame(alignment:.leading)
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEpisode = episode
                    }
                    
                    Button(action: {
                        withAnimation {
                            player.togglePlayback(for: episode)
                        }
                        print("Playing episode")
                    }) {
                        if player.isPlayingEpisode(episode) {
                            if player.isLoadingEpisode(episode) {
                                PPSpinner(color: Color.heading)
                            } else {
                                Image(systemName: "waveform")
                                    .symbolEffect(.variableColor.cumulative.dimInactiveLayers.nonReversing)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        } else {
                            Image(systemName: episode.isPlayed ? "arrow.clockwise" : "play.fill")
                        }
                    }
                    .buttonStyle(PPButton(
                        type: .transparent,
                        colorStyle: .monochrome,
                        iconOnly: true,
                        customColors: ButtonCustomColors(
                            foreground: .heading,
                            background: .surface
                        )))
                }
                .frame(maxWidth:.infinity)
                .padding(6)
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
            .padding(8)
            .frame(maxWidth:.infinity)
            .sheet(item: $selectedEpisode) { episode in
                EpisodeView(episode: episode)
                    .modifier(PPSheet(showOverlay: false))
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
