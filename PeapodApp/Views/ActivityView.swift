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
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var statsManager = StatisticsManager.shared
    @State private var showingUpgrade = false
    @State private var recentlyPlayed: [Episode] = []
    @State private var longestEpisode: Episode?
    @State private var topPlayedEpisodes: [Episode] = []
    @State private var favoriteDayName: String = "Loading..."
    @State private var favoriteDayCount: Int = 0
    @State private var weeklyData: [WeeklyListeningData] = []
    @State private var rotationAngle: Double = 0
    @State private var selectedEpisodeForNavigation: Episode? = nil
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
        .onAppear {
            loadEpisodeData()
        }
        .task {
            await statsManager.loadStatistics(from: context)
            await loadFavoriteDay()
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
                weeklyData: weeklyData,
                favoriteDayName: favoriteDayName,
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
                    
                    // Rest of your view code remains the same...
                    FadeInView(delay: 0.1) {
                        VStack(spacing:16) {
                            WeeklyListeningLineChart(
                                weeklyData: weeklyData,
                                favoriteDayName: favoriteDayName
                            )
                            
                            HStack(spacing:2) {
                                Text("You listen the most on")
                                    .textDetail()
                                
                                Text(favoriteDayName)
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
    
    // MARK: - Data Loading
    private func loadEpisodeData() {
        recentlyPlayed = getPlayedEpisodes(context: context)
            .sorted { ($0.playedDate ?? Date.distantPast) > ($1.playedDate ?? Date.distantPast) }
            .prefix(5)
            .compactMap { $0 }
        
        let playedEpisodes = getPlayedEpisodes(context: context)
        longestEpisode = playedEpisodes
            .filter { $0.actualDuration > 0 }
            .max { $0.actualDuration < $1.actualDuration }
        
        topPlayedEpisodes = playedEpisodes
            .sorted { $0.playCount > $1.playCount }
            .prefix(5)
            .compactMap { $0 }
    }
    
    private func loadFavoriteDay() async {
        let weeklyListeningData = getWeeklyListeningData(context: context)
        
        if let (dayOfWeek, count) = getMostPopularListeningDay(context: context) {
            let dayName = dayName(from: dayOfWeek)
            
            DispatchQueue.main.async {
                withAnimation(.easeInOut) {
                    self.weeklyData = weeklyListeningData
                    self.favoriteDayName = dayName
                    self.favoriteDayCount = count
                }
            }
        } else {
            DispatchQueue.main.async {
                self.weeklyData = weeklyListeningData
                self.favoriteDayName = "No data yet"
            }
        }
    }
    
    // Helper functions remain the same...
    private func getWeeklyListeningData(context: NSManagedObjectContext) -> [WeeklyListeningData] {
        let playedEpisodes = getPlayedEpisodes(context: context)
        var dayCounts: [Int: Int] = [:]
        let calendar = Calendar.current
        
        for episode in playedEpisodes {
            if let playedDate = episode.playedDate {
                let dayOfWeek = calendar.component(.weekday, from: playedDate)
                dayCounts[dayOfWeek, default: 0] += 1
            }
        }
        
        let maxCount = dayCounts.values.max() ?? 1
        
        return (1...7).map { dayOfWeek in
            let count = dayCounts[dayOfWeek] ?? 0
            let percentage = maxCount > 0 ? Double(count) / Double(maxCount) : 0.0
            let dayAbbreviation = dayAbbreviation(from: dayOfWeek)
            
            return WeeklyListeningData(
                dayOfWeek: dayOfWeek,
                count: count,
                percentage: percentage,
                dayAbbreviation: dayAbbreviation
            )
        }
    }
    
    private func getMostPopularListeningDay(context: NSManagedObjectContext) -> (Int, Int)? {
        let playedEpisodes = getPlayedEpisodes(context: context)
        var dayCounts: [Int: Int] = [:]
        let calendar = Calendar.current
        
        for episode in playedEpisodes {
            if let playedDate = episode.playedDate {
                let dayOfWeek = calendar.component(.weekday, from: playedDate)
                dayCounts[dayOfWeek, default: 0] += 1
            }
        }
        
        return dayCounts.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }
    
    private func dayName(from dayOfWeek: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let date = Calendar.current.date(from: DateComponents(weekday: dayOfWeek))!
        return formatter.string(from: date)
    }
    
    private func dayAbbreviation(from dayOfWeek: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        let date = Calendar.current.date(from: DateComponents(weekday: dayOfWeek))!
        return String(formatter.string(from: date).prefix(1))
    }
}
