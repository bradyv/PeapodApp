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
                        LazyHStack(spacing:8) {
                            if episodesViewModel.queue.isEmpty {
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
                                        Image("Peapod.mono")
                                            .resizable()
                                            .frame(width:32, height:23)
                                            .opacity(0.35)
                                        
                                        Text("Nothing to play")
                                            .titleCondensed()
                                        
                                        Text(subscriptions.isEmpty ? "Add some podcasts to get started." : "New episodes are automatically added.")
                                            .textBody()
                                    }
                                    .offset(x:-16)
                                    .frame(maxWidth: .infinity)
                                    .zIndex(1)
                                }
                                .frame(width: UIScreen.main.bounds.width, height: 250)
                            } else {
                                ForEach(Array(episodesViewModel.queue.enumerated()), id: \.element.id) { index, episode in
                                    QueueItemView(episode: episode, index: index, namespace: namespace) {
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
                            scrollOffset = CGFloat(nearest.key)
                            if episodesViewModel.queue.indices.contains(Int(scrollOffset)) {
                                currentEpisodeID = episodesViewModel.queue[Int(scrollOffset)].id
                            }
                        }
                    }
                    .onChange(of: scrollTarget) { id in
                        if let id = id {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .leading)
                            }
                        }
                    }
                    .disabled(episodesViewModel.queue.isEmpty)
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal,16, for: .scrollContent)
                    .onChange(of: episodesViewModel.queue.first?.id) { oldID, newID in
                        if let id = newID {
                            DispatchQueue.main.async {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .leading)
                                }
                            }
                        }
                    }
                }
                
                if episodesViewModel.queue.count > 1 {
                    GeometryReader { geo in
                        HStack(spacing: 8) {
                            Spacer()
                            ForEach(episodesViewModel.queue.indices, id: \.self) { index in
                                let isCurrent = index == Int(scrollOffset)
                                let episode = episodesViewModel.queue[index]
                                
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
                                    if let id = episodesViewModel.queue[index].id {
                                        withAnimation {
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
            .onTapGesture {
                episodeSelectionManager.selectEpisode(episode)
            }
    }
}
