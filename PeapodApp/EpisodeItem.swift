//
//  EpisodeItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct EpisodeItem: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var episode: Episode
    var displayedInQueue: Bool = false
    var displayedFullscreen: Bool = false
    @State private var selectedPodcast: Podcast? = nil
    
    var body: some View {
        VStack(alignment:.leading) {
            // Podcast Info Row
            HStack {
                HStack {
                    KFImage(URL(string:episode.podcast?.image ?? ""))
                        .resizable()
                        .frame(width: 24, height: 24)
                        .cornerRadius(3)
                    
                    Text(parseHtml(episode.podcast?.title ?? "Podcast title"))
                        .lineLimit(1)
                        .foregroundStyle(displayedInQueue ? Color.white : Color.heading)
                        .textDetailEmphasis()
                }
                .onTapGesture {
                    selectedPodcast = episode.podcast
                }
                
                Text(episode.airDate ?? Date.distantPast, style: .date)
                    .foregroundStyle(displayedInQueue ? Color.white.opacity(0.75) : Color.text)
                    .textDetail()
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            
            // Episode Meta
            VStack(alignment:.leading, spacing:12) {
                Text(episode.title ?? "Episode title")
                    .foregroundStyle(displayedInQueue ? Color.white : Color.heading)
                    .titleCondensed()
                
                Text(episode.episodeDescription ?? "Episode description")
                    .foregroundStyle(displayedInQueue ? Color.white.opacity(0.75) : Color.heading)
                    .textBody()
            }
            .frame(maxWidth:.infinity)
            
            // Episode Actions
            if !displayedFullscreen {
                HStack {
                    Button(action: {
                        print("Playing \(episode.title ?? "Episode title")")
                    }) {
                        Label(formatDuration(seconds: Int(episode.duration)), systemImage: "play.circle.fill")
                    }
                    .buttonStyle(
                        displayedInQueue
                            ? PPButton(
                                type: .filled,
                                colorStyle: .monochrome,
                                customColors: ButtonCustomColors(
                                    foreground: .black,
                                    background: .white
                                )
                            )
                            : PPButton(
                                type: .filled,
                                colorStyle: .monochrome
                            )
                    )
                    
                    Button(action: {
                        episode.isQueued.toggle()
                        try? episode.managedObjectContext?.save()
                        
                        print("Queued \(episode.title ?? "Episode title")")
                    }) {
                        Label(episode.isQueued ? "Queued" : "Add to queue", systemImage: episode.isQueued ? "checkmark" : "plus.circle")
                    }
                    .buttonStyle(
                        displayedInQueue
                            ? PPButton(
                                type: .transparent,
                                colorStyle: .monochrome,
                                customColors: ButtonCustomColors(
                                    foreground: .white,
                                    background: .white.opacity(0.15)
                                )
                            )
                            : PPButton(
                                type: .transparent,
                                colorStyle: .tinted
                            )
                    )
                }
            }
        }
        .sheet(item: $selectedPodcast) { podcast in
            PodcastDetailView(feedUrl: podcast.feedUrl ?? "")
                .modifier(PPSheet())
        }
        .frame(maxWidth:.infinity)
        .onAppear {
            Task.detached(priority: .background) {
                ColorTintManager.applyTintIfNeeded(to: episode, in: context)
            }
        }
    }
}
