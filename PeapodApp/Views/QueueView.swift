//
//  QueueView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct QueueView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @EnvironmentObject var player: AudioPlayerManager
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest())
    var subscriptions: FetchedResults<Podcast>
    
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollTarget: String? = nil
    @Namespace private var namespace
    
    private var hasQueue: Bool {
        !episodesViewModel.queue.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QueueHeader(hasQueue: hasQueue)
            QueueScrollView(
                hasQueue: hasQueue,
                subscriptions: subscriptions,
                scrollOffset: $scrollOffset,
                scrollTarget: $scrollTarget,
                namespace: namespace
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Queue Header
struct QueueHeader: View {
    let hasQueue: Bool
    
    var body: some View {
        Group {
            if hasQueue {
                NavigationLink {
                    QueueListView()
                        .navigationTitle("Up Next")
                } label: {
                    headerContent
                }
            } else {
                headerContent
            }
        }
    }
    
    private var headerContent: some View {
        HStack(alignment: .center) {
            Text("Up Next")
                .titleSerifMini()
            
            if hasQueue {
                Image(systemName: "chevron.right")
                    .textDetailEmphasis()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Queue Scroll View
struct QueueScrollView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @EnvironmentObject var player: AudioPlayerManager
    
    let hasQueue: Bool
    let subscriptions: FetchedResults<Podcast>
    @Binding var scrollOffset: CGFloat
    @Binding var scrollTarget: String?
    let namespace: Namespace.ID
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    if hasQueue {
                        queueContent
                    } else {
                        emptyQueueContent
                    }
                }
                .scrollTargetLayout()
            }
            .scrollClipDisabled(true)
            .scrollTargetBehavior(.viewAligned)
            .scrollDisabled(!hasQueue)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .onPreferenceChange(ScrollOffsetKey.self) { values in
                handleScrollOffsetChange(values)
            }
            .onChange(of: scrollTarget) { _, id in
                handleScrollTargetChange(id, proxy: proxy)
            }
            .onChange(of: episodesViewModel.queue.first?.id) { _, newID in
                handleQueueFirstChange(newID, proxy: proxy)
            }
            .onChange(of: player.currentEpisode?.id) { _, newEpisodeID in
                handleCurrentEpisodeChange(newEpisodeID, proxy: proxy)
            }
            .onAppear {
                scrollToCurrentEpisodeIfNeeded(proxy: proxy)
            }
        }
    }
    
    @ViewBuilder
    private var queueContent: some View {
        ForEach(Array(episodesViewModel.queue.enumerated()), id: \.element.id) { index, episode in
            NavigationLink {
                EpisodeView(episode: episode)
                    .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
            } label: {
                QueueItemView(episode: episode, index: index)
                    .matchedTransitionSource(id: episode.id, in: namespace)
            }
        }
    }
    
    @ViewBuilder
    private var emptyQueueContent: some View {
        ZStack {
            EmptyQueueBackground()
            EmptyQueueMessage(subscriptions: subscriptions)
                .offset(x: -16)
                .frame(maxWidth: .infinity)
                .zIndex(1)
        }
        .frame(width: UIScreen.main.bounds.width, height: 450)
    }
    
    // MARK: - Event Handlers
    private func handleScrollOffsetChange(_ values: [Int: CGFloat]) {
        guard let nearest = values.min(by: { abs($0.value) < abs($1.value) }) else { return }
        
        let newScrollOffset = CGFloat(nearest.key)
        guard scrollOffset != newScrollOffset else { return }
        
        scrollOffset = newScrollOffset
        NotificationCenter.default.post(
            name: .queueScrollPositionChanged,
            object: Int(scrollOffset)
        )
    }
    
    private func handleScrollTargetChange(_ id: String?, proxy: ScrollViewProxy) {
        guard let id = id else { return }
        withAnimation {
            proxy.scrollTo(id, anchor: .leading)
        }
    }
    
    private func handleQueueFirstChange(_ newID: String?, proxy: ScrollViewProxy) {
        guard let id = newID else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(id, anchor: .leading)
            }
        }
    }
    
    private func handleCurrentEpisodeChange(_ newEpisodeID: String?, proxy: ScrollViewProxy) {
        guard let episodeID = newEpisodeID,
              episodesViewModel.queue.contains(where: { $0.id == episodeID }) else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo(episodeID, anchor: .leading)
            }
        }
    }
    
    private func scrollToCurrentEpisodeIfNeeded(proxy: ScrollViewProxy) {
        guard let currentEpisode = player.currentEpisode,
              let episodeID = currentEpisode.id,
              episodesViewModel.queue.contains(where: { $0.id == episodeID }) else { return }
        
        proxy.scrollTo(episodeID, anchor: .leading)
    }
}

// MARK: - Empty Queue Background
struct EmptyQueueBackground: View {
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    EmptyQueueItem()
                        .opacity(0.15)
                }
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .mask(
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.8)
                )
            )
        }
    }
}

// MARK: - Empty Queue Message
struct EmptyQueueMessage: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    let subscriptions: FetchedResults<Podcast>
    
    private var hasSubscriptions: Bool {
        !subscriptions.isEmpty
    }
    
    var body: some View {
        VStack {
            Text(hasSubscriptions ? "All caught up 🎉" : "Nothing up next")
                .titleCondensed()
            
            Text(hasSubscriptions ? "New releases are automatically added to Up Next." : "Follow some podcasts to get started.")
                .textBody()
            
            Spacer().frame(height: 24)
            
            if hasSubscriptions {
                EmptyQueueActions()
            } else {
                FindPodcastButton()
            }
        }
    }
}

// MARK: - Empty Queue Actions
struct EmptyQueueActions: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            NavigationLink {
                LatestEpisodesView(mini: false)
                    .navigationTitle("Recent Releases")
            } label: {
                Label("Recent Releases", systemImage: "calendar")
                    .textButton()
            }
            .buttonStyle(.bordered)
            
            if !episodesViewModel.favs.isEmpty {
                FavoritesButton()
            }
        }
    }
}

// MARK: - Find Podcast Button
struct FindPodcastButton: View {
    var body: some View {
        NavigationLink {
            PodcastSearchView()
        } label: {
            Label("Find a Podcast", systemImage: "plus.magnifyingglass")
                .padding(.vertical, 4)
                .foregroundStyle(.white)
                .textBodyEmphasis()
        }
        .buttonStyle(.glassProminent)
    }
}

// MARK: - Favorites Button
struct FavoritesButton: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    
    private var favoritePreviews: [(offset: Int, element: Episode)] {
        Array(episodesViewModel.favs.prefix(3).enumerated().reversed())
    }
    
    private let customOffsets: [(x: CGFloat, y: CGFloat)] = [
        (x: 2, y: -5),   // back
        (x: 8, y: 0),    // middle
        (x: 0, y: 4)     // front
    ]
    
    var body: some View {
        NavigationLink {
            FavEpisodesView(mini: false)
                .navigationTitle("Favorites")
        } label: {
            HStack(spacing: 16) {
                FavoriteStackIcon(
                    episodes: favoritePreviews,
                    offsets: customOffsets
                )
                
                Text("Favorites")
                    .textButton()
            }
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Favorite Stack Icon
struct FavoriteStackIcon: View {
    let episodes: [(offset: Int, element: Episode)]
    let offsets: [(x: CGFloat, y: CGFloat)]
    
    var body: some View {
        ZStack {
            // Background placeholders
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let offset = offsets[index]
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.background.opacity(0.15))
                        .frame(width: 14, height: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(lineWidth: 1)
                                .blendMode(.destinationOut)
                        )
                        .offset(x: offset.x, y: offset.y)
                }
            }
            .compositingGroup()
            
            // Episode artworks
            ZStack {
                ForEach(episodes, id: \.element.id) { index, episode in
                    let offset = offsets[index]
                    ArtworkView(url: episode.podcast?.image ?? "", size: 14, cornerRadius: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(lineWidth: 1)
                                .blendMode(.destinationOut)
                        )
                        .offset(x: offset.x, y: offset.y)
                }
            }
            .compositingGroup()
        }
    }
}

// MARK: - Queue Item View
struct QueueItemView: View {
    @EnvironmentObject var player: AudioPlayerManager
    let episode: Episode
    let index: Int
    
    var body: some View {
        QueueItem(data: EpisodeCellData(from: episode), episode: episode)
            .id(episode.id)
            .lineLimit(3)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: ScrollOffsetKey.self,
                            value: [index: geo.frame(in: .global).minX]
                        )
                }
            )
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.5)
            }
    }
}

// MARK: - Scroll Offset Preference Key
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
