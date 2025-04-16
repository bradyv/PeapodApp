//
//  NowPlaying.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-06.
//

import SwiftUI
import CoreData
import Kingfisher

struct NowPlaying: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var selectedEpisode: Episode? = nil
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "nowPlayingItem == YES"),
        animation: .default
    ) var nowPlaying: FetchedResults<Episode>
    
    var body: some View {
        
        ZStack {
            if let episode = nowPlaying.first(where: { !$0.isFault && !$0.isDeleted && $0.id != nil }) {
                ZStack(alignment: .bottomLeading) {
                    EpisodeItem(episode: episode, displayedInQueue: true)
                        .id(episode.id)
                        .lineLimit(3)
                        .padding(.horizontal)

                    VStack {
                        KFImage(URL(string: episode.episodeImage ?? episode.podcast?.image ?? ""))
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                    startPoint: .top,
                                    endPoint: .init(x: 0.5, y: 0.7)
                                )
                            )
                            .allowsHitTesting(false)
                        Spacer()
                    }
                }
                .onTapGesture {
                    selectedEpisode = episode
                }
                .sheet(item: $selectedEpisode) { episode in
                    EpisodeView(episode: episode)
                        .modifier(PPSheet())
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .move(edge:.top).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.easeOut(duration: 0.3), value: player.currentEpisode?.id)
    }
}
