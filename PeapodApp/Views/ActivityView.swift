//
//  ActivityView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-10.
//

import SwiftUI
import CoreData
import Kingfisher

struct ActivityView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @StateObject private var userManager = UserManager.shared
    @StateObject private var statsManager = StatisticsManager.shared
    @State private var recentlyPlayed: [Episode] = []
    @State private var longestEpisode: Episode?
    @State private var topPlayedEpisodes: [Episode] = []
    
    @FetchRequest(
        fetchRequest: Podcast.topPlayedRequest(),
        animation: .default
    )
    var topPodcasts: FetchedResults<Podcast>
    
    var mini: Bool = false
    
    var body: some View {
        Group {
            if mini {
                miniView
            } else {
                fullView
            }
        }
        .task {
            // Only load episode data for full view
            // All stats are already available in statsManager
            guard !mini else { return }
            await loadFullViewData()
        }
    }
    
    @ViewBuilder
    var miniView: some View {
        HStack(alignment:.bottom, spacing:28) {
            let podiumOrder = [2,1,0]
            let reordered: [(Int, Podcast)] = podiumOrder.compactMap { index in
                guard index < topPodcasts.count else { return nil }
                return (index, topPodcasts[index])
            }
            let hours = statsManager.totalPlayedHours
            let hourString = hours > 1 ? "Hours" : "Hour"
            
            VStack(alignment:.leading,spacing:10) {
                Text("Listened")
                    .textDetail()
                
                VStack(alignment:.leading,spacing:0) {
                    Text("\(hours)")
                        .titleCondensed()
                        .monospaced()
                        .contentTransition(.numericText())
                    
                    Text("\(hourString)")
                        .textDetailEmphasis()
                }
            }
            .fixedSize()
            
            VStack(alignment:.leading,spacing:10) {
                Text("Favorite")
                    .textDetail()
                
                ForEach(reordered.reversed().prefix(1), id: \.1.id) { (index, podcast) in
                    ArtworkView(url: podcast.image ?? "", size: 40, cornerRadius: 11)
                }
            }
            .fixedSize()
            
            WeeklyListeningLineChart(
                weeklyData: statsManager.weeklyData,
                favoriteDayName: statsManager.favoriteDayName,
                mini: true
            )
            .frame(maxWidth:.infinity)
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }
    
    @ViewBuilder
    var fullView: some View {
        ScrollView {
            VStack(spacing:32) {
                if recentlyPlayed.isEmpty {
                    ZStack {
                        VStack {
                            ForEach(0..<2, id: \.self) { _ in
                                EmptyEpisodeCell()
                            }
                        }
                        .mask(
                            LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.8))
                        )
                        
                        VStack {
                            Text("No listening activity")
                                .titleCondensed()
                            
                            Text("Listen to some podcasts already.")
                                .textBody()
                        }
                    }
                } else {
                    let podiumOrder = [2,1,0]
                    let reordered: [(Int, Podcast)] = podiumOrder.compactMap { index in
                        guard index < topPodcasts.count else { return nil }
                        return (index, topPodcasts[index])
                    }
                    let hours = statsManager.totalPlayedHours
                    let hourString = hours > 1 ? "Hours" : "Hour"
                    let episodeString = statsManager.playCount > 1 ? "Episodes" : "Episode"
                    
                    VStack(alignment:.leading) {
                        HStack {
                            VStack(alignment:.leading) {
                                Text(userManager.memberTypeDisplay)
                                    .titleCondensed()
                                
                                Text("Since \(userManager.userDateString)")
                                    .textDetail()
                            }
                            
                            Spacer()
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(hours)")
                                        .titleCondensed()
                                        .monospaced()
                                        .contentTransition(.numericText())
                                    
                                    Text("\(hourString) listened")
                                        .textDetail()
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("\(statsManager.playCount)")
                                        .titleCondensed()
                                        .monospaced()
                                        .contentTransition(.numericText())
                                    
                                    Text("\(episodeString) played")
                                        .textDetail()
                                }
                            }
                        }
                        .frame(maxWidth:.infinity)
                    }
                    .padding(.horizontal)
                    
                    FadeInView(delay: 0.1) {
                        VStack(spacing:16) {
                            WeeklyListeningLineChart(
                                weeklyData: statsManager.weeklyData,
                                favoriteDayName: statsManager.favoriteDayName
                            )
                            
                            HStack(spacing:2) {
                                Text("You listen the most on")
                                    .textDetail()
                                
                                Text(statsManager.favoriteDayName)
                                    .textDetailEmphasis()
                            }
                        }
                    }
                    
                    FadeInView(delay: 0.2) {
                        HStack(spacing:32) {
                            VStack {
                                Text("My Top Podcasts")
                                    .titleCondensed()
                                    .frame(maxWidth:.infinity,alignment:.leading)
                                    
                                ForEach(reordered.reversed(), id: \.1.id) { (index, podcast) in
                                    HStack {
                                        ArtworkView(url: podcast.image ?? "", size: 24, cornerRadius: 6)
                                        
                                        Text(podcast.title ?? "")
                                            .textDetailEmphasis()
                                            .lineLimit(1)
                                        
                                        Text(podcast.formattedPlayedHours)
                                            .textDetail()
                                    }
                                    .opacity(index == 1 ? 0.75 : (index == 2 ? 0.50 : 1))
                                    .frame(maxWidth:.infinity, alignment:.leading)
                                }
                            }
                            .frame(maxWidth:.infinity, alignment:.leading)
                            
                            ZStack {
                                ForEach(reordered, id: \.1.id) { (index, podcast) in
                                    KFImage(URL(string:podcast.image ?? ""))
                                        .resizable()
                                        .frame(width: 96, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius:24))
                                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.blendMode(.overlay), lineWidth: 1.5))
                                        .offset(
                                            x: index == 1 ? 4 : (index == 2 ? 10 : 0),
                                            y: index == 1 ? 0 : (index == 2 ? -5 : 0)
                                        )
                                        .rotationEffect(
                                            .degrees(index == 1 ? 10 : (index == 2 ? 18 : 0))
                                        )
                                }
                            }
                            .padding(.trailing,24)
                        }
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .padding(.horizontal)
                    }
                    
                    if let longestEpisode = longestEpisode {
                        FadeInView(delay:0.3) {
                            VStack {
                                Text("Longest Completed Episode")
                                    .titleCondensed()
                                    .frame(maxWidth:.infinity,alignment:.leading)
                                
                                HStack(spacing:16) {
                                    ZStack(alignment:.bottom) {
                                        ArtworkView(url: longestEpisode.episodeImage ?? longestEpisode.podcast?.image ?? "", size: 100, cornerRadius: 24)
                                            .mask {
                                                LinearGradient(gradient: Gradient(colors: [.background, .clear]), startPoint: .top, endPoint: .bottom)
                                            }
                                        
                                        HStack(alignment:.center) {
                                            let duration = Int(longestEpisode.actualDuration)
                                            Image(systemName: "laurel.leading")
                                                .foregroundStyle(.accent)
                                                .font(.system(size: 32))
                                            
                                            Text("\(formatDuration(seconds: duration))")
                                                .textDetailEmphasis()
                                            
                                            Image(systemName: "laurel.trailing")
                                                .foregroundStyle(.accent)
                                                .font(.system(size: 32))
                                        }
                                    }
                                    .scrollClipDisabled(true)
                                    
                                    VStack(alignment:.leading) {
                                        Text(longestEpisode.podcast?.title ?? "Podcast title")
                                            .lineLimit(1)
                                            .textDetailEmphasis()
                                        
                                        Text(longestEpisode.title ?? "Episode title")
                                            .titleCondensed()
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .frame(maxWidth:.infinity, alignment:.leading)
                                }
                                .frame(maxWidth:.infinity)
                                
                            }
                            .frame(maxWidth:.infinity,alignment:.leading)
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .toolbar {
            if !episodesViewModel.queue.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    MiniPlayer()
                    Spacer()
                    MiniPlayerButton()
                }
            }
        }
        .background(Color.background)
        .navigationTitle("My Stats")
        .navigationBarTitleDisplayMode(.large)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
    
    // MARK: - Data Loading (Full View Only)
    
    private func loadFullViewData() async {
        // Perform Core Data work on background context
        let bgContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        bgContext.parent = context
        
        await bgContext.perform {
            let playedEpisodes = getPlayedEpisodes(context: bgContext)
            
            let recentlyPlayedData = playedEpisodes
                .sorted { ($0.playedDate ?? Date.distantPast) > ($1.playedDate ?? Date.distantPast) }
                .prefix(5)
                .compactMap { $0 }
            
            let longestEpisodeData = playedEpisodes
                .filter { $0.actualDuration > 0 }
                .max { $0.actualDuration < $1.actualDuration }
            
            let topPlayedEpisodesData = playedEpisodes
                .sorted { $0.playCount > $1.playCount }
                .prefix(5)
                .compactMap { $0 }
            
            DispatchQueue.main.async {
                self.recentlyPlayed = Array(recentlyPlayedData)
                self.longestEpisode = longestEpisodeData
                self.topPlayedEpisodes = Array(topPlayedEpisodesData)
            }
        }
    }
}
