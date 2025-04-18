//
//  QueueView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI

struct QueueView: View {
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "name == %@", "Queue"),
        animation: .interactiveSpring()
    ) var queuePlaylists: FetchedResults<Playlist>

    var queue: [Episode] {
        (queuePlaylists.first?.episodes as? Set<Episode>)?
            .filter { !$0.nowPlayingItem }
            .sorted(by: { $0.queuePosition < $1.queuePosition }) ?? []
    }
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "isSubscribed == YES"),
        animation: .default
    ) var subscriptions: FetchedResults<Podcast>
    @State private var selectedEpisode: Episode? = nil

    // Add scroll proxy trigger
    @State private var frontEpisodeID: UUID? = nil
    
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollTarget: String? = nil
    @State private var activeCard: Episode?

    var body: some View {
        
        VStack(alignment: .leading, spacing: 12) {
            Text("Up Next")
                .titleSerif()
                .padding(.leading)
                .padding(.bottom, 4)

            VStack(spacing:0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing:16) {
                            if queue.isEmpty {
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
                                NowPlayingItem()
                                
                                ForEach(queue.indices, id: \.self) { index in
                                    QueueItem(episode: queue[index])
                                        .lineLimit(3)
                                        .id(queue[index])
                                        .scrollTransition { content, phase in
                                            content
                                                .opacity(phase.isIdentity ? 1 : 0.5) // Apply opacity animation
                                                .scaleEffect(y: phase.isIdentity ? 1 : 0.92) // Apply scale animation
                                        }
                                        .onTapGesture {
                                            selectedEpisode = queue[index]
                                        }
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .disabled(queue.isEmpty)
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $activeCard)
                    .contentMargins(.horizontal,16, for: .scrollContent)
                    .sheet(item: $selectedEpisode) { episode in
                        EpisodeView(episode: episode)
                            .modifier(PPSheet())
                    }
                }
                
                if queue.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(queue.indices, id: \.self) { index in
                            let episode = queue[index]
                            Button {
                                withAnimation {
                                    activeCard = episode
                                }
                            } label: {
                                Image(systemName: activeCard == episode ? "circle.fill" : "circle")
                                .foregroundStyle(Color(uiColor: .systemGray3))
                            }
                        }
                    }
                    .padding(.horizontal)
                    .frame(maxWidth:.infinity)
                    .contentShape(Rectangle())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top,24)
        .onAppear {
            activeCard = queue.first
        }
        .onChange(of: queue.first) { newFirst in
            if let newFirst = newFirst {
                DispatchQueue.main.async {
                    activeCard = newFirst
                }
            }
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:] // UUID not Int

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
