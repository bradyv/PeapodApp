//
//  ActivityView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-10.
//

import SwiftUI
import CoreData
import Kingfisher

struct ActivityView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject private var userManager = UserManager.shared
    @State private var statistics = AppStatistics(podcastCount: 0, totalPlayedSeconds: 0, subscribedCount: 0, playCount: 0)
    @State private var showingUpgrade = false
    @State private var recentlyPlayed: [Episode] = []
    @State private var longestEpisode: Episode?
    @State private var topPlayedEpisodes: [Episode] = []
    
    @FetchRequest(
        fetchRequest: Podcast.topPlayedRequest(),
        animation: .default
    )
    var topPodcasts: FetchedResults<Podcast>
    
    @State var degreesRotating = 0.0
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    @State private var isSpinning = false
    @State private var favoriteDayName: String = "Loading..."
    @State private var favoriteDayCount: Int = 0
    @State private var weeklyData: [WeeklyListeningData] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing:16) {
                if recentlyPlayed.isEmpty {
                    ZStack {
                        VStack {
                            ForEach(0..<2, id: \.self) { _ in
                                EmptyEpisodeItem()
                                    .opacity(0.03)
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
                    let hours = Int(statistics.totalPlayedSeconds) / 3600
                    let hourString = hours > 1 ? "Hours" : "Hour"
                    let episodeString = statistics.playCount > 1 ? "Episodes" : "Episode"
                    
                    VStack(alignment:.leading) {
                        Image("peapod-mark")
                        
                        HStack {
                            VStack(alignment:.leading) {
                                Text("Listener")
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
                                    Text("\(statistics.playCount)")
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
                    
                    FadeInView(delay: 0.1) {
                        WeeklyListeningLineChart(
                            weeklyData: weeklyData,
                            favoriteDayName: favoriteDayName
                        )
                    }
                    
                    FadeInView(delay: 0.2) {
                        VStack(alignment:.leading) {
                            FadeInView(delay: 0.2) {
                                Text("My Top Podcasts")
                                    .titleCondensed()
                                    .multilineTextAlignment(.center)
                            }
                            
                            HStack(spacing:32) {
                                ZStack {
                                    ForEach(reordered, id: \.1.id) { (index, podcast) in
                                        ArtworkView(url: podcast.image ?? "", size: 96, cornerRadius: 16)
                                            .offset(
                                                x: index == 1 ? 4 : (index == 2 ? 10 : 0),
                                                y: index == 1 ? 0 : (index == 2 ? -10 : 0)
                                            )
                                            .rotationEffect(
                                                .degrees(index == 1 ? 10 : (index == 2 ? 10 : 0))
                                            )
                                    }
                                }
                                
                                VStack {
                                    ForEach(reordered.reversed(), id: \.1.id) { (index, podcast) in
                                        HStack {
                                            ArtworkView(url: podcast.image ?? "", size: 24, cornerRadius: 3)
                                            
                                            Text(podcast.title ?? "")
                                                .textDetailEmphasis()
                                                .lineLimit(1)
                                            
                                            Text(podcast.formattedPlayedHours)
                                                .textDetail()
                                        }
                                        .frame(maxWidth:.infinity, alignment:.leading)
                                    }
                                }
                                .frame(maxWidth:.infinity, alignment:.leading)
                            }
                            .frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }
                    
                    if let longestEpisode = longestEpisode {
                        FadeInView(delay: 0.3) {
                            VStack(alignment:.leading) {
                                HStack(alignment:.top) {
                                    Image("peapod-mark")
                                    Spacer()
                                }
                                
                                FadeInView(delay: 0.3) {
                                    Text("Longest Completed Episode")
                                        .foregroundStyle(Color.white)
                                        .titleCondensed()
                                        .multilineTextAlignment(.center)
                                }
                                
                                FadeInView(delay: 0.4) {
                                    HStack {
                                        let duration = Int(longestEpisode.actualDuration)
                                        ArtworkView(url:longestEpisode.episodeImage ?? longestEpisode.podcast?.image ?? "", size: 44, cornerRadius: 8)
                                        
                                        VStack(alignment:.leading) {
                                            HStack {
                                                Text(longestEpisode.podcast?.title ?? "Unknown Podcast")
                                                    .foregroundStyle(Color.white)
                                                    .textDetailEmphasis()
                                                
                                                Text(getRelativeDateString(from: longestEpisode.airDate ?? Date()))
                                                    .foregroundStyle(Color.white)
                                                    .textDetail()
                                            }
                                            Text(longestEpisode.title ?? "Untitled")
                                                .foregroundStyle(Color.white)
                                                .titleCondensed()
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth:.infinity,alignment:.leading)
                                        
                                        FadeInView(delay: 0.5) {
                                            Text("\(formatDuration(seconds: duration))")
                                                .foregroundStyle(Color.black)
                                                .textDetailEmphasis()
                                                .padding(.vertical, 3)
                                                .padding(.horizontal, 8)
                                                .background(Color.white)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth:.infinity,alignment:.leading)
                            .foregroundStyle(Color.white)
                            .padding()
                            .background {
                                ArtworkView(url:longestEpisode.episodeImage ?? longestEpisode.podcast?.image ?? "", size: 500, cornerRadius: 0)
                                    .blur(radius: 128)
                                Image("Noise")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .opacity(0.5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius:16))
                            .glassEffect(in: .rect(cornerRadius: 16))
                        }
                    }
                }
            }
        }
        .navigationTitle("My Stats")
        .scrollEdgeEffectStyle(.soft, for: .all)
        .contentMargins(.horizontal,16, for:.scrollContent)
        .onAppear {
            isSpinning = true
            loadEpisodeData()
        }
        .task {
            await loadStatistics()
            await loadFavoriteDay()
        }
    }
    
    // MARK: - Data Loading
    private func loadEpisodeData() {
        // Load recently played episodes
        recentlyPlayed = getPlayedEpisodes(context: context)
            .sorted { ($0.playedDate ?? Date.distantPast) > ($1.playedDate ?? Date.distantPast) }
            .prefix(5)
            .compactMap { $0 }
        
        // Load longest episode (episode with highest actualDuration that's been played)
        let playedEpisodes = getPlayedEpisodes(context: context)
        longestEpisode = playedEpisodes
            .filter { $0.actualDuration > 0 }
            .max { $0.actualDuration < $1.actualDuration }
        
        // Load top played episodes (episodes with highest play count)
        topPlayedEpisodes = playedEpisodes
            .sorted { $0.playCount > $1.playCount }
            .prefix(5)
            .compactMap { $0 }
    }
    
    // MARK: - Statistics Loading
    private func loadStatistics() async {
        do {
            let newStats = try await AppStatistics.load(from: context)
            
            // Wait to allow the UI to render with zeros, then animate the updates
            try? await Task.sleep(for: .nanoseconds(1))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut) {
                    statistics = newStats
                }
            }
        } catch {
            LogManager.shared.error("Error loading statistics: \(error)")
            // Keep default zero values on error
        }
    }
    
    private func loadFavoriteDay() async {
        do {
            // Load weekly data using new boolean approach
            let weeklyListeningData = getWeeklyListeningData(context: context)
            
            // Find favorite day
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
        } catch {
            LogManager.shared.error("Error loading favorite day: \(error)")
            DispatchQueue.main.async {
                self.favoriteDayName = "Unable to load"
            }
        }
    }
    
    // MARK: - Helper Functions
    private func getWeeklyListeningData(context: NSManagedObjectContext) -> [WeeklyListeningData] {
        let playedEpisodes = getPlayedEpisodes(context: context)
        
        // Group by day of week
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
