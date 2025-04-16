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
    @State private var isVisible = false
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "nowPlayingItem == YES"),
        animation: .default
    ) var nowPlaying: FetchedResults<Episode>
    var animationNamespace: Namespace.ID
    
    var body: some View {
        
        ZStack {
            if isVisible, let episode = nowPlaying.first(where: { !$0.isFault && !$0.isDeleted && $0.id != nil }) {
                VStack {
                    EpisodeItem(episode: episode, displayedInQueue: true)
                        .matchedGeometryEffect(id: episode.id!, in: animationNamespace, isSource: false)
                        .id(episode.id)
                        .lineLimit(3)
                        .padding(.horizontal)
                }
                .onTapGesture {
                    selectedEpisode = episode
                }
                .sheet(item: $selectedEpisode) { episode in
                    EpisodeView(episode: episode)
                        .modifier(PPSheet())
                }
            }
        }
        .onChange(of: nowPlaying.first?.id) { _, newID in
            isVisible = false

            // Delay just long enough for the QueueView to remove it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Don’t animate re-appearance — matchedGeometry handles that
                isVisible = true
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isVisible = true
            }
        }
    }
}
