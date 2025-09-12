//
//  QueueItem.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct QueueItem: View {
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    
    // Computed properties based on unified state
    private var isPlaying: Bool {
        player.isPlayingEpisode(episode)
    }
    
    private var isLoading: Bool {
        player.isLoadingEpisode(episode)
    }
    
    var body: some View {
        let frame = UIScreen.main.bounds.width - 48
        let artwork = episode.episodeImage ?? episode.podcast?.image ?? ""
        
        ZStack(alignment: .bottomLeading) {
            VStack {
                KFImage(URL(string: artwork))
                    .resizable()
                    .frame(width: frame, height: frame)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                       startPoint: .init(x:0.5,y:0.4), endPoint: .init(x:0.5,y:0.8))
                    )
                    .allowsHitTesting(false)
                Spacer()
            }
            
            EpisodeItem(episode: episode, showActions: true, displayedInQueue: true)
                .lineLimit(3)
                .padding()
                .frame(maxWidth: .infinity)
        }
        .frame(width: frame, height: 450)
        .background(
            KFImage(URL(string: artwork))
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .scaleEffect(x: 1, y: -1)
                .blur(radius: 44)
                .opacity(0.5)
        )
        .background(Color.black)
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(Color.white, lineWidth: 1).blendMode(.overlay))
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }
}

struct EmptyQueueItem: View {
    var body: some View {
        let frame = UIScreen.main.bounds.width - 32
        VStack {
            HStack {
                Rectangle()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width: 96, height: 12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width: 32, height: 12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            VStack(alignment: .leading) {
                Rectangle()
                    .frame(width: 100, height: 24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            VStack(alignment: .leading) {
                Rectangle()
                    .frame(width: 188, height: 12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.bottom, 16)
        }
        .frame(width: frame, height: 250, alignment: .bottomLeading)
        .background(Color.heading.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(Color.heading.opacity(0.5), lineWidth: 1))
    }
}
