//
//  QueueView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct QueueView: View {
    @Binding var currentEpisodeID: String?
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @ObservedObject private var queueManager = QueueManager.shared
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest())
    var subscriptions: FetchedResults<Podcast>
    @State private var selectedEpisode: Episode? = nil
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollTarget: String? = nil
    
    var namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Up Next")
                .titleSerif()
                .padding(.leading)
                .padding(.bottom, 4)

            VStack(spacing:0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing:8) {
                            if queueManager.isEmpty {
                                ZStack {
                                    GeometryReader { geometry in
                                        HStack(spacing:16) {
                                            ForEach(0..<2, id: \.self) { _ in
                                                EmptyQueueItem()
                                                    .opacity(0.15)
                                            }
                                        }
                                        .frame(width: geometry.size.width, alignment:.leading)
                                        .mask(
                                            LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.8))
                                        )
                                    }
                                    
                                    VStack {
                                        Text("Nothing up next")
                                            .titleCondensed()
                                        
                                        Text(subscriptions.isEmpty ? "Add some podcasts to get started." : "New episodes are automatically added.")
                                            .textBody()
                                        
                                        if !episodesViewModel.saved.isEmpty {
                                            let items = Array(episodesViewModel.saved.prefix(3).enumerated().reversed())
                                            Button(action: {
                                                for (_, episode) in items {
                                                    withAnimation(.spring(duration: 0.6, bounce: 0.3)) {
                                                        queueManager.toggle(episode)
                                                    }
                                                }
                                            }) {
                                                HStack(spacing:12) {
                                                    let customOffsets: [(x: CGFloat, y: CGFloat)] = [
                                                        (x: 2, y: -5),   // back
                                                        (x: 8, y: 0),  // middle
                                                        (x: 0, y: 4)     // front
                                                    ]
                                                    
                                                    ZStack {
                                                        ZStack {
                                                            ForEach(0..<3, id: \.self) { index in
                                                                let offset = customOffsets[index]
                                                                RoundedRectangle(cornerRadius:3)
                                                                    .fill(Color.background.opacity(0.15))
                                                                    .frame(width:14,height:14)
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
                                                    
                                                    Text("Add from Play Later")
                                                }
                                            }
                                            .buttonStyle(PPButton(type:.filled, colorStyle:.monochrome))
                                        }
                                    }
                                    .offset(x:-16)
                                    .frame(maxWidth: .infinity)
                                    .zIndex(1)
                                }
                                .frame(width: UIScreen.main.bounds.width, height: 250)
                                .transition(.opacity.animation(.spring(duration: 0.8, bounce: 0.4)))
                            } else {
                                ForEach(Array(queueManager.episodes.enumerated()), id: \.element.id) { index, episode in
                                    QueueItemView(episode: episode, index: index, namespace: namespace) {
                                        selectedEpisode = episode
                                    }
                                    .transition(.opacity.animation(.spring(duration: 0.8, bounce: 0.4)))
                                }
                            }
                        }
                        .scrollTargetLayout()
                        .animation(.spring(duration: 0.6, bounce: 0.3), value: queueManager.episodes.map { $0.id })
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .onPreferenceChange(ScrollOffsetKey.self) { values in
                        if let nearest = values.min(by: { abs($0.value) < abs($1.value) }) {
                            scrollOffset = CGFloat(nearest.key)
                            if queueManager.episodes.indices.contains(Int(scrollOffset)) {
                                currentEpisodeID = queueManager.episodes[Int(scrollOffset)].id
                            }
                        }
                    }
                    .onChange(of: scrollTarget) { _, id in
                        if let id = id {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo(id, anchor: .leading)
                            }
                        }
                    }
                    .scrollDisabled(queueManager.isEmpty)
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal,16, for: .scrollContent)
                    .onChange(of: queueManager.first?.id) { oldID, newID in
                        if let id = newID {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo(id, anchor: .leading)
                                }
                            }
                        }
                    }
                }
                
                if queueManager.count > 1 {
                    GeometryReader { geo in
                        HStack(spacing: 8) {
                            Spacer()
                            ForEach(queueManager.episodes.indices, id: \.self) { index in
                                let isCurrent = index == Int(scrollOffset)
                                
                                VStack {
                                    Capsule()
                                        .fill(isCurrent ? Color.heading : Color.heading.opacity(0.3))
                                        .frame(width: isCurrent ? 18 : 6, height: 6)
                                        .contentShape(Circle())
                                        .transition(.opacity)
                                        .animation(.easeOut(duration: 0.3), value: isCurrent)
                                }
                                .frame(height:44)
                                .fixedSize()
                                .onTapGesture {
                                    if let id = queueManager.episodes[index].id {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            scrollTarget = id
                                        }
                                    }
                                }
                            }
                            Spacer()
                        }
                        .frame(maxWidth: geo.size.width, alignment:.leading)
                        .clipped()
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                        .animation(.easeInOut(duration: 0.3), value: queueManager.episodes.count)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top,24)
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
    let episode: Episode
    let index: Int
    var namespace: Namespace.ID
    var onSelect: () -> Void

    // Add local state tracking to reduce redraw frequency
    @State private var playbackPosition: Double = 0
    @ObservedObject private var player = AudioPlayerManager.shared
    
    var body: some View {
        QueueItem(episode: episode, namespace: namespace)
            .matchedTransitionSource(id: episode.id, in: namespace)
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
            .onAppear {
                // Cache the playback position to avoid frequent reads
                playbackPosition = player.getProgress(for: episode)
            }
            .onTapGesture {
                // Ensure we don't animate during tap
                withAnimation(.none) {
                    episodeSelectionManager.selectEpisode(episode)
                }
            }
            // Only update when progress actually changes significantly
            .onChange(of: player.progress) { _, newProgress in
                if abs(playbackPosition - player.getProgress(for: episode)) > 1.0 {
                    playbackPosition = player.getProgress(for: episode)
                }
            }
    }
}
