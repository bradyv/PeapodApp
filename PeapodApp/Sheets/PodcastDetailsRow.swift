//
//  PodcastDetailsRow.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-09-29.
//

import SwiftUI

struct PodcastDetailsRow: View {
    @ObservedObject var episode: Episode
    var displayedInQueue: Bool = false
    
    var body: some View {
        HStack {
            NavigationLink {
                PodcastDetailView(feedUrl: episode.podcast?.feedUrl ?? "")
            } label: {
                HStack {
                    ArtworkView(url: episode.podcast?.image ?? "", size: 24, cornerRadius: 6)
                    
                    Text(episode.podcast?.title ?? "Podcast title")
                        .lineLimit(1)
                        .foregroundStyle(displayedInQueue ? Color.white : .heading)
                        .textDetailEmphasis()
                }
            }
            
            Text(getRelativeDateString(from: episode.airDate ?? Date.distantPast))
                .foregroundStyle(displayedInQueue ? Color.white.opacity(0.75) : .text)
                .textDetail()
        }
        .frame(maxWidth: .infinity, alignment: displayedInQueue ? .leading : .center)
    }
}
