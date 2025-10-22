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
    @StateObject private var userManager = UserManager.shared
    @State private var selectedEpisodeForNavigation: Episode? = nil
    @State private var showUpgrade = false
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest(), animation: .none)
    var subscriptions: FetchedResults<Podcast>
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:32) {
                userStatsSection
                    .padding(.horizontal)
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
        .sheet(isPresented: $showUpgrade) {
            UpgradeView()
                .modifier(PPSheet())
        }
    }
    
    @ViewBuilder
    private var userStatsSection: some View {
        VStack(alignment:.leading) {
            if userManager.hasPremiumAccess {
                ActivityView(mini:true)
            } else {
                HStack(spacing:28) {
                    VStack(alignment:.leading,spacing:10) {
                        SkeletonItem(width:44, height:8)
                        VStack(alignment:.leading,spacing:4) {
                            SkeletonItem(width:68, height:24)
                            SkeletonItem(width:33, height:12)
                        }
                    }
                    .fixedSize()
                    
                    VStack(alignment:.leading,spacing:10) {
                        SkeletonItem(width:44, height:8)
                        SkeletonItem(width:40, height:40)
                    }
                    .fixedSize()
                    
                    WeeklyListeningLineChart(
                        weeklyData: WeeklyListeningLineChart.mockData,
                        favoriteDayName: "Friday",
                        mini: true
                    )
                    .frame(maxWidth:.infinity)
                }
                .frame(maxWidth:.infinity, alignment:.leading)
            }
            
            Spacer().frame(height:16)
            
            moreStatsButton
        }
        .padding()
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius:26))
    }
    
    @ViewBuilder
    private var moreStatsButton: some View {
        if userManager.hasPremiumAccess {
            NavigationLink {
                ActivityView()
            } label: {
                Text("View More")
            }
            .buttonStyle(.glass)
        } else {
            Button {
                showUpgrade = true
            } label: {
                Label("Unlock Stats", systemImage: "lock.fill")
            }
            .buttonStyle(.glassProminent)
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
