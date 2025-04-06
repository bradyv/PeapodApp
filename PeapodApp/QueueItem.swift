//
//  QueueItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct QueueItem: View {
    @ObservedObject var episode: Episode
    
    var body: some View {
        let frame = CGFloat(250)
        
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
                                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.7))
                    )
                Spacer()
            }
        }
        .frame(width: frame, height: 350)
        .background(Color(hex: episode.episodeTint)?.darkened(by:0.3) ?? Color(hex: episode.podcast?.podcastTint)?.darkened(by:0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
    }
}

struct EmptyQueueItem: View {
    var body: some View {
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
                    .frame(maxWidth:.infinity).frame(height:24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width:100, height:24)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            .padding(.horizontal)
            
            VStack(alignment:.leading) {
                Rectangle()
                    .frame(maxWidth:.infinity).frame(height:12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Rectangle()
                    .frame(width:188, height:12)
                    .foregroundStyle(Color.heading)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            .padding(.horizontal).padding(.bottom,16)
        }
        .frame(width: 250, height: 350, alignment:.bottomLeading)
        .background(Color.heading.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
