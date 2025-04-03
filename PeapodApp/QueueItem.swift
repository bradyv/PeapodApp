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
        ZStack(alignment:.bottomLeading) {
            EpisodeItem(episode:episode, displayedInQueue: true)
                .lineLimit(3)
                .padding()
                .frame(maxWidth: .infinity)
            
            VStack {
                KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                    .resizable()
                    .frame(width: 300, height: 300)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.7))
                    )
                Spacer()
            }
        }
        .frame(width: 300, height: 400)
        .background(Color(hex: episode.episodeTint)?.darkened(by:0.5) ?? Color(hex: episode.podcast?.podcastTint)?.darkened(by:0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
    }
}
