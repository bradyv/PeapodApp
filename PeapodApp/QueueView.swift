//
//  QueueView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI

struct QueueView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.queuePosition)],
        predicate: NSPredicate(format: "isQueued == YES"),
        animation: .interactiveSpring()
    )
    var queue: FetchedResults<Episode>
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Up Next")
                .titleSerif()
                .padding(.leading)
                .padding(.bottom, 4)

            VStack {
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
                                ForEach(queue.indices, id: \.self) { index in
                                    QueueItem(episode: queue[index])
                                        .id(queue[index].id)
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
                    .onPreferenceChange(ScrollOffsetKey.self) { values in
                        if let nearest = values.min(by: { abs($0.value) < abs($1.value) }) {
                            scrollOffset = CGFloat(nearest.key)
                        }
                    }
                    .onChange(of: scrollTarget) { id in
                        if let id = id {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .leading)
                            }
                        }
                    }
                    .disabled(queue.isEmpty)
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal,16, for: .scrollContent)
                    .sheet(item: $selectedEpisode) { episode in
                        EpisodeView(episode: episode)
                            .modifier(PPSheet())
                    }
                    .onChange(of: queue.first?.id) { oldID, newID in
                        if let id = newID {
                            DispatchQueue.main.async {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .leading)
                                }
                            }
                        }
                    }
                }
                
                if queue.count > 1 {
                    HStack(spacing: 12) {
                        ForEach(queue.indices, id: \.self) { index in
                            let isCurrent = index == Int(scrollOffset)

                            VStack {
                                Capsule()
                                    .fill(isCurrent ? Color.heading : Color.heading.opacity(0.3))
                                    .frame(width: 18, height: 4)
                                    .contentShape(Circle())
                            }
                            .frame(height:44)
                            .onTapGesture {
                                if let id = queue[index].id {
                                    withAnimation {
                                        scrollTarget = id
                                    }
                                }
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
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
