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
            
            if episode.isQueued && !displayedInQueue {
                HStack(spacing:4) {
                    Image(systemName:"rectangle.portrait.on.rectangle.portrait.angled")
                        .textDetail()
                    
                    Text("Up Next")
                        .textDetail()
                }
            } else if episode.isPlayed && !displayedInQueue {
                HStack(spacing:4) {
                    Image(systemName:"checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.heading)
                        .textDetail()
                    
                    Text("Played")
                        .textDetail()
                }
            } else {
//                Text(getRelativeDateString(from: episode.airDate ?? Date.distantPast))
                RoundedRelativeDateView(date: episode.airDate ?? Date.now)
                    .foregroundStyle(displayedInQueue ? Color.white.opacity(0.75) : .text)
                    .textDetail()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
