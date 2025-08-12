//
//  QueueView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct QueueView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @EnvironmentObject var player: AudioPlayerManager
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest())
    var subscriptions: FetchedResults<Podcast>
    @State private var selectedEpisode: Episode? = nil
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollTarget: String? = nil

    var body: some View {
        VStack(alignment: .leading) {
            Text("Up Next")
                .titleSerifMini()
                .padding(.leading).padding(.top)
            
            VStack(spacing:0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 8) {
                            if episodesViewModel.queue.isEmpty {
                                ZStack {
                                    GeometryReader { geometry in
                                        HStack(spacing: 16) {
                                            ForEach(0..<2, id: \.self) { _ in
                                                EmptyQueueItem()
                                                    .opacity(0.15)
                                            }
                                        }
                                        .frame(width: geometry.size.width, alignment: .leading)
                                        .mask(
                                            LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.8))
                                        )
                                    }
                                    
                                    VStack {
                                        Text("Nothing up next")
                                            .titleCondensed()
                                        
                                        Text(subscriptions.isEmpty ? "Follow some podcasts to get started." : "New releases are automatically added.")
                                            .textBody()
                                        
                                        // UPDATED: Change from episodesViewModel.saved to episodesViewModel.favs
                                        if !episodesViewModel.favs.isEmpty {
                                            let items = Array(episodesViewModel.favs.prefix(3).enumerated().reversed())
                                            Button(action: {
                                                for (_, episode) in items {
                                                    withAnimation {
                                                        toggleQueued(episode)
                                                    }
                                                }
                                            }) {
                                                HStack(spacing: episodesViewModel.favs.count > 2 ? 12 : 8) {
                                                    let customOffsets: [(x: CGFloat, y: CGFloat)] = [
                                                        (x: 2, y: -5),   // back
                                                        (x: 8, y: 0),  // middle
                                                        (x: 0, y: 4)     // front
                                                    ]
                                                    
                                                    ZStack {
                                                        ZStack {
                                                            ForEach(0..<3, id: \.self) { index in
                                                                let offset = customOffsets[index]
                                                                RoundedRectangle(cornerRadius: 3)
                                                                    .fill(Color.background.opacity(0.15))
                                                                    .frame(width: 14, height: 14)
                                                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.heading, lineWidth: 1))
                                                                    .offset(x: offset.x, y: offset.y)
                                                            }
                                                        }
                                                        
                                                        ZStack {
                                                            ForEach(items, id: \.element.id) { index, episode in
                                                                let offset = customOffsets[index]
                                                                ArtworkView(url: episode.podcast?.image ?? "", size: 14, cornerRadius: 3)
                                                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.heading, lineWidth: 1))
                                                                    .offset(x: offset.x, y: offset.y)
                                                            }
                                                        }
                                                    }
                                                    
                                                    Text("Add from Favorites")
                                                }
                                            }
                                            .buttonStyle(PPButton(type: .filled, colorStyle: .monochrome))
                                        }
                                    }
                                    .offset(x: -16)
                                    .frame(maxWidth: .infinity)
                                    .zIndex(1)
                                }
                                .frame(width: UIScreen.main.bounds.width, height: 250)
                            } else {
                                ForEach(Array(episodesViewModel.queue.enumerated()), id: \.element.id) { index, episode in
                                    QueueItemView(episode: episode, index: index) {
                                        selectedEpisode = episode
                                    }
                                    .onTapGesture {
                                        selectedEpisode = episode
                                    }
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .onPreferenceChange(ScrollOffsetKey.self) { values in
                        if let nearest = values.min(by: { abs($0.value) < abs($1.value) }) {
                            let newScrollOffset = CGFloat(nearest.key)
                            
                            // Only update if the scroll position actually changed
                            if scrollOffset != newScrollOffset {
                                scrollOffset = newScrollOffset
                                
                                // Post notification for MainBackground
                                NotificationCenter.default.post(
                                    name: .queueScrollPositionChanged,
                                    object: Int(scrollOffset)
                                )
                            }
                        }
                    }
                    .onChange(of: scrollTarget) { _, id in
                        if let id = id {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .leading)
                            }
                        }
                    }
                    .scrollDisabled(episodesViewModel.queue.isEmpty)
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .onChange(of: episodesViewModel.queue.first?.id) { oldID, newID in
                        if let id = newID {
                            DispatchQueue.main.async {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .leading)
                                }
                            }
                        }
                    }
                    // Auto-scroll to currently playing episode when it changes
                    .onChange(of: player.currentEpisode?.id) { _, newEpisodeID in
                        if let episodeID = newEpisodeID,
                           episodesViewModel.queue.contains(where: { $0.id == episodeID }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo(episodeID, anchor: .leading)
                                }
                            }
                        }
                    }
                }
                
                GeometryReader { geo in
                    HStack(spacing: 8) {
                        Spacer()
                        ForEach(episodesViewModel.queue.indices, id: \.self) { index in
                            let isCurrent = index == Int(scrollOffset)
                            
                            VStack {
                                Capsule()
                                    .fill(isCurrent ? Color.heading : Color.heading.opacity(0.3))
                                    .frame(width: isCurrent ? 18 : 6, height: 6)
                                    .contentShape(Circle())
                                    .transition(.opacity)
                                    .animation(.easeOut(duration: 0.3), value: isCurrent)
                            }
                            .frame(height: 44)
                            .fixedSize()
                            .onTapGesture {
                                if let id = episodesViewModel.queue[index].id {
                                    withAnimation {
                                        scrollTarget = id
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .frame(maxWidth: geo.size.width, alignment: .leading)
                    .clipped()
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .opacity(episodesViewModel.queue.count > 1 ? 1 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $selectedEpisode) { episode in
            EpisodeView(episode: episode)
                .modifier(PPSheet())
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct QueueItemView: View {
    @EnvironmentObject var episodeSelectionManager: EpisodeSelectionManager
    @EnvironmentObject var player: AudioPlayerManager
    let episode: Episode
    let index: Int
    var onSelect: () -> Void
    @State private var selectedEpisode: Episode? = nil
    
    var body: some View {
        QueueItem(episode: episode)
            .id(episode.id)
            .lineLimit(3)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self,
                                    value: [index: geo.frame(in: .global).minX])
                }
            )
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.5)
                    .scaleEffect(y: phase.isIdentity ? 1 : 0.85)
            }
    }
}
