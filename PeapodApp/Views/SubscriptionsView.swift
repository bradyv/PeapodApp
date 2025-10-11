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
            VStack(alignment:.leading,spacing:32) {
                LatestEpisodesView(mini:true, maxItems: 5)
                FavEpisodesView(mini: true, maxItems: 5)
                
                VStack(spacing: 8) {
                    HStack(alignment: .center) {
                        Text("Following")
                            .titleSerifMini()
                            .padding(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Actual grid with Add button + (possibly empty) real subscriptions
                    LazyVGrid(columns: columns, spacing: 16) {
                        // Real podcasts - optimized for scroll performance
                        ForEach(subscriptions, id: \.objectID) { podcast in
                            NavigationLink {
                                PodcastDetailView(feedUrl: podcast.feedUrl ?? "")
                            } label: {
                                ArtworkView(url: podcast.image ?? "", cornerRadius: 24)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(maxWidth:.infinity, alignment:.leading)
        }
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
        let frame = (UIScreen.main.bounds.width - 80) / 3
        if !subscriptions.isEmpty {
            VStack(spacing: 8) {
                NavigationLink {
                    SubscriptionsView()
                        .navigationTitle("Library")
                } label: {
                    HStack(alignment: .center) {
                        Text("Library")
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
                                ArtworkView(url: podcast.image ?? "", size: frame, cornerRadius: 24)
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
