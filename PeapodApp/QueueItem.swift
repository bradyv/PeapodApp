//
//  QueueItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct QueueItem: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var episode: Episode
    
    var body: some View {
        let frame = UIScreen.main.bounds.width - 32

        ZStack(alignment:.bottomLeading) {
            EpisodeItem(episode:episode, displayedInQueue: true)
                .lineLimit(3)
                .padding()
                .frame(maxWidth: .infinity)
            
            VStack {
                KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                    .resizable()
                    .frame(width: frame, height: frame)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.6))
                    )
                    .allowsHitTesting(false)
                Spacer()
            }
        }
        .frame(width: frame, height: 400)
        .background(Color.tint(for:episode, darkened: true))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25), lineWidth: 1))
    }
}

struct EmptyQueueItem: View {
    var body: some View {
        let frame = UIScreen.main.bounds.width - 32
        VStack {
            HStack {
                Rectangle()
                    .frame(width:24, height:24)
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
            .frame(maxWidth:.infinity, alignment:.leading)
            .padding(.horizontal)
            
            VStack(alignment:.leading) {
                Rectangle()
                    .frame(width:100, height:24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            .padding(.horizontal)
            
            VStack(alignment:.leading) {
                
                Rectangle()
                    .frame(width:188, height:12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            .padding(.horizontal).padding(.bottom,16)
        }
        .frame(width: frame, height: 250, alignment:.bottomLeading)
        .background(Color.heading.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
