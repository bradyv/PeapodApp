//
//  SubscriptionsView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct SubscriptionsView: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @State private var selectedEpisodeForNavigation: Episode? = nil
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest(), animation: .none)
    var subscriptions: FetchedResults<Podcast>
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    
    var body: some View {
        ScrollView {
            // Actual grid with Add button + (possibly empty) real subscriptions
            LazyVGrid(columns: columns, spacing: 16) {
                // Real podcasts - optimized for scroll performance
                ForEach(subscriptions, id: \.objectID) { podcast in
                    NavigationLink {
                        PodcastDetailView(feedUrl: podcast.feedUrl ?? "")
                    } label: {
                        PodcastGridItem(podcast: podcast)
                    }
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .background(Color.background)
        .toolbar {
            if !episodesViewModel.queue.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    MiniPlayer()
                    Spacer()
                    MiniPlayerButton()
                }
            }
        }
    }
}

struct SubscriptionsRow: View {
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest(), animation: .none)
    var subscriptions: FetchedResults<Podcast>
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    
    var body: some View {
        let frame = (UIScreen.main.bounds.width - 72) / 3
        if !subscriptions.isEmpty {
            VStack(spacing: 8) {
                NavigationLink {
                    SubscriptionsView()
                        .navigationTitle("Following")
                } label: {
                    HStack(alignment: .center) {
                        Text("Following")
                            .titleSerifMini()
                            .padding(.leading)
                        
                        Image(systemName: "chevron.right")
                            .textDetailEmphasis()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(subscriptions, id: \.objectID) { podcast in
                            NavigationLink {
                                PodcastDetailView(feedUrl: podcast.feedUrl ?? "")
                            } label: {
                                PodcastGridItem(podcast: podcast)
                                    .frame(width: frame, height: frame)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - Optimized Podcast Grid Item for Scroll Performance
struct PodcastGridItem: View {
    let podcast: Podcast
    
    var body: some View {
        KFImage(URL(string:podcast.image ?? ""))
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.blendMode(.overlay), lineWidth: 1))
    }
}
