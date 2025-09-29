//
//  EpisodeDetails.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-09-29.
//

import SwiftUI

struct EpisodeDetails: View {
    @ObservedObject var episode: Episode
    var displayedInQueue: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Line\nLine\nLine")
                .titleCondensed()
                .lineLimit(displayedInQueue ? 4 : 3, reservesSpace: true)
                .frame(maxWidth: .infinity)
                .hidden()
                .overlay(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title ?? "Episode title")
                            .foregroundStyle(displayedInQueue ? .white : .heading)
                            .titleCondensed()
                            .lineLimit(2)
                            .layoutPriority(1)
                            .multilineTextAlignment(.leading)
                        
                        Text(parseHtml(episode.episodeDescription ?? "Episode description", flat: true))
                            .foregroundStyle(displayedInQueue ? .white.opacity(0.75) : .text)
                            .textBody()
                            .lineLimit(2)
                            .layoutPriority(0)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
