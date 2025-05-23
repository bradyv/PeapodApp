//
//  NowPlaying.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-06.
//

import SwiftUI
import Kingfisher

struct NowPlayingSplash: View {
    @FetchRequest(fetchRequest: Episode.queueFetchRequest(), animation: .interactiveSpring())
    var nowPlaying: FetchedResults<Episode>
    var episodeID: String?
    @State private var displayedEpisode: Episode?
    
    var body: some View {
        FadeInView(delay:0.2) {
            ZStack {
               if let episode = displayedEpisode {
                SplashImage(image: episode.episodeImage ?? episode.podcast?.image ?? "")
                    .transition(.opacity)
                    .id(episode.id) // Forces view identity change to animate transition
                    .animation(.easeInOut(duration: 0.3), value: episode.id)
                }
            }
            .onChange(of: episodeID) { _, newID in
                if let id = newID {
                    if let match = nowPlaying.first(where: { $0.id == id }) {
                        withAnimation {
                            displayedEpisode = match
                        }
                    }
                }
            }
            .onChange(of: nowPlaying.count) {
                if nowPlaying.isEmpty {
                    withAnimation {
                        displayedEpisode = nil
                    }
                }
            }
        }
    }
}

struct NowPlaying: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var episodeSelectionManager: EpisodeSelectionManager
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var selectedEpisode: Episode? = nil
    @State private var spacing: CGFloat = -38
    @State private var infoMaxWidth: CGFloat = 100
    @State private var isNowPlaying = false
    @State private var isLoading = false
    @State private var currentForwardInterval: Double = AudioPlayerManager.shared.forwardInterval
    @State private var currentBackwardInterval: Double = AudioPlayerManager.shared.backwardInterval
    @FetchRequest(fetchRequest: Episode.queueFetchRequest(), animation: .interactiveSpring())
    var nowPlaying: FetchedResults<Episode>
    var displayedInQueue: Bool = false
    var namespace: Namespace.ID
    var onTap: ((Episode) -> Void)?

    var body: some View {
        
        if let episode = nowPlaying.first {
            VStack(alignment:.center) {
                Spacer()
                
                HStack {
                    Button {
                        episodeSelectionManager.selectEpisode(episode)
                    } label: {
                        HStack {
                            KFImage(URL(string: episode.episodeImage ?? episode.podcast?.image ?? ""))
                                .resizable()
                                .frame(width:36, height:36)
                                .clipShape(Circle())
                            
                            VStack(alignment:.leading, spacing:0) {
                                Text(episode.podcast?.title ?? "Podcast title")
                                    .textDetail()
                                    .lineLimit(1)
                                
                                Text(episode.title ?? "Episode title")
                                    .textBody()
                                    .lineLimit(1)
                            }
                            .frame(maxWidth:infoMaxWidth,alignment:.leading)
                            .maskEdge(.trailing)
                        }
                    }
                    
                    HStack(spacing: spacing) {
//                        let isLoading = player.isLoadingEpisode(episode)
                        Button(action: {
                            player.skipBackward(seconds:currentBackwardInterval)
                            print("Seeking back")
                        }) {
                            Label("Go back", systemImage: "\(String(format: "%.0f", currentBackwardInterval)).arrow.trianglehead.counterclockwise")
                        }
                        .disabled(!player.isPlayingEpisode(episode))
                        .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true, customColors:ButtonCustomColors(foreground: player.isPlayingEpisode(episode) ? .heading : .heading.opacity(0), background: .surface)))
                        .zIndex(-1)
                        
                        Button(action: {
                            player.togglePlayback(for: episode)
                            print("Playing episode")
                        }) {
                            if player.isLoadingEpisode(episode) {
                                PPSpinner(color: Color.background)
                            } else if player.isPlayingEpisode(episode) {
                                Image(systemName: "pause")
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
                            player.skipForward(seconds:currentForwardInterval)
                            print("Seeking forward")
                        }) {
                            Label("Go forward", systemImage: "\(String(format: "%.0f", currentForwardInterval)).arrow.trianglehead.clockwise")
                        }
                        .disabled(!player.isPlayingEpisode(episode))
                        .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true, customColors:ButtonCustomColors(foreground: player.isPlayingEpisode(episode) ? .heading : .heading.opacity(0), background: .surface)))
                        .zIndex(-1)
                    }
                    .onAppear {
                        updateNowPlayingState()
                    }
                    .onChange(of: player.state) {
                        updateNowPlayingState()
                    }
                    .onReceive(player.$backwardInterval) { newBackwardInterval in
                        currentBackwardInterval = newBackwardInterval
                    }
                    .onReceive(player.$forwardInterval) { newForwardInterval in
                        currentForwardInterval = newForwardInterval
                    }
                    
                }
                .padding(8)
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
                .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 3)
            }
            .frame(maxWidth:.infinity)
        }
    }
    
    private func updateNowPlayingState() {
        guard let episode = nowPlaying.first else { return }
        let isPlaying = player.isPlayingEpisode(episode)
        if isPlaying != isNowPlaying {
            isNowPlaying = isPlaying
            withAnimation(.easeInOut(duration: 0.3)) {
                spacing = isPlaying ? -4 : -38
                infoMaxWidth = isPlaying ? 180 : 75
            }
        }
    }
}
