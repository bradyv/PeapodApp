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
        FadeInView(delay:0.2) {
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
            .onChange(of: nowPlaying.count) { _ in
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
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var selectedEpisode: Episode? = nil
    @State private var spacing: CGFloat = -38
    @State private var infoMaxWidth: CGFloat = 100
    @State private var isNowPlaying = false
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.queuePosition)],
        predicate: NSPredicate(format: "nowPlaying == YES"),
        animation: .interactiveSpring()
    )
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
                        onTap?(episode)
                    } label: {
                        HStack {
                            KFImage(URL(string: episode.episodeImage ?? episode.podcast?.image ?? ""))
                                .resizable()
                                .frame(width:36, height:36)
                                .clipShape(Circle())
                                .matchedTransitionSource(id: episode.id, in: namespace)
                            
                            VStack(alignment:.leading, spacing:0) {
                                Text(episode.podcast?.title ?? "Podacst title")
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
                        Button(action: {
                            player.skipBackward(seconds:15)
                            print("Seeking back")
                        }) {
                            Label("Go back", systemImage: "15.arrow.trianglehead.counterclockwise")
                        }
                        .disabled(!player.isPlayingEpisode(episode))
                        .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true, customColors:ButtonCustomColors(foreground: player.isPlayingEpisode(episode) ? .heading : .heading.opacity(0), background: .surface)))
                        .zIndex(-1)
                        
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
                            player.skipForward(seconds:30)
                            print("Seeking back")
                        }) {
                            Label("Go back", systemImage: "30.arrow.trianglehead.clockwise")
                        }
                        .disabled(!player.isPlayingEpisode(episode))
                        .buttonStyle(PPButton(type:.transparent,colorStyle:.monochrome,iconOnly: true, customColors:ButtonCustomColors(foreground: player.isPlayingEpisode(episode) ? .heading : .heading.opacity(0), background: .surface)))
                        .zIndex(-1)
                    }
                    .onAppear {
                        updateNowPlayingState()
                    }
                    .onReceive(player.$isPlaying.combineLatest(player.$currentEpisode)) { _, _ in
                        updateNowPlayingState()
                    }
                    .onChange(of: player.isPlayingEpisode(episode)) { isPlaying in
                        updateNowPlayingState()
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
            .padding(8)
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
