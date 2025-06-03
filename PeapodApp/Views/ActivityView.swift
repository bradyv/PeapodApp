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
    @ObservedObject private var userManager = UserManager.shared
    @State private var statistics = AppStatistics(podcastCount: 0, episodeCount: 0, totalPlayedSeconds: 0, subscribedCount: 0, playCount: 0)
    @State private var showingUpgrade = false
    
    @FetchRequest(
        fetchRequest: Episode.recentlyPlayedRequest(limit: 5),
        animation: .interactiveSpring()
    )
    var played: FetchedResults<Episode>
    
    @FetchRequest(
        fetchRequest: Episode.longestPlayedEpisodeRequest(),
        animation: .default
    )
    var longestEpisodes: FetchedResults<Episode>
    
    @FetchRequest(fetchRequest: Episode.topPlayedEpisodesRequest(), animation: .default)
    var topPlayedEpisodes: FetchedResults<Episode>
    
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
    var namespace: Namespace.ID
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:52)
            Text("My Stats")
                .titleSerif()
                .frame(maxWidth:.infinity, alignment:.leading)
            
            if played.isEmpty {
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
                let podiumOrder = [1, 0, 2]
                let reordered: [(Int, Podcast)] = podiumOrder.compactMap { index in
                    guard index < topPodcasts.count else { return nil }
                    return (index, topPodcasts[index])
                }
                let hours = Int(statistics.totalPlayedSeconds) / 3600
                let hourString = hours > 1 ? "Hours" : "Hour"
                let episodeString = statistics.playCount > 1 ? "Episodes" : "Episode"
                let podcastString = statistics.podcastCount > 1 ? "podcasts" : "podcast"
                
                FadeInView(delay: 0.5) {
                    VStack(alignment:.leading) {
                        Image("peapod-plus-mark")
                        
                        VStack(alignment:.leading) {
                            Text(userManager.memberTypeDisplay)
                                .foregroundStyle(Color.white)
                                .titleCondensed()
                            
                            Text("Since \(userManager.userDateString)")
                                .foregroundStyle(Color.white)
                                .textDetail()
                        }
                        
                        HStack {
                            FadeInView(delay:0.6) {
                                VStack(alignment:.leading, spacing: 8) {
                                    Image(systemName:"airpods.max")
                                        .foregroundStyle(Color.white)
                                    
                                    VStack(alignment:.leading) {
                                        Text("\(hours)")
                                            .foregroundStyle(Color.white)
                                            .titleSerif()
                                            .monospaced()
                                            .contentTransition(.numericText())
                                        
                                        Text("\(hourString) listened")
                                            .foregroundStyle(Color.white)
                                            .textDetail()
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(cardBackgroundGradient)
                                .background(.white.opacity(0.15))
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .inset(by: 1)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                )
                            }
                            
                            FadeInView(delay:0.7) {
                                VStack(alignment:.leading, spacing:8) {
                                    Image(systemName:"play.circle")
                                        .foregroundStyle(Color.white)
                                        .symbolRenderingMode(.hierarchical)
                                    
                                    VStack(alignment:.leading) {
                                        Text("\(statistics.playCount)")
                                            .foregroundStyle(Color.white)
                                            .titleSerif()
                                            .monospaced()
                                            .contentTransition(.numericText())
                                        
                                        Text("\(episodeString) played")
                                            .foregroundStyle(Color.white)
                                            .textDetail()
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(cardBackgroundGradient)
                                .background(.white.opacity(0.15))
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .inset(by: 1)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                )
                            }
                        }
                        .frame(maxWidth:.infinity, alignment:.leading)
                        
//                        HStack {
//                            FadeInView(delay:0.8) {
//                                VStack(alignment:.leading, spacing: 8) {
//                                    Image(systemName:"widget.small")
//                                        .foregroundStyle(Color.white)
//                                    
//                                    VStack(alignment:.leading) {
//                                        Text("\(statistics.podcastCount)")
//                                            .foregroundStyle(Color.white)
//                                            .titleSerif()
//                                            .monospaced()
//                                            .contentTransition(.numericText())
//                                        
//                                        Text("Unique \(podcastString)")
//                                            .foregroundStyle(Color.white)
//                                            .textDetail()
//                                    }
//                                }
//                                .padding(16)
//                                .frame(maxWidth: .infinity, alignment: .topLeading)
//                                .background(cardBackgroundGradient)
//                                .background(.white.opacity(0.15))
//                                .cornerRadius(16)
//                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
//                                .overlay(
//                                    RoundedRectangle(cornerRadius: 16)
//                                        .inset(by: 1)
//                                        .stroke(.white.opacity(0.15), lineWidth: 1)
//                                )
//                            }
//                            
//                            FadeInView(delay:0.9) {
//                                VStack(alignment:.leading, spacing:8) {
//                                    Image(systemName:"checkmark.circle")
//                                        .foregroundStyle(Color.white)
//                                        .symbolRenderingMode(.hierarchical)
//                                    
//                                    VStack(alignment:.leading) {
//                                        Text("91%")
//                                            .foregroundStyle(Color.white)
//                                            .titleSerif()
//                                            .monospaced()
//                                            .contentTransition(.numericText())
//                                        
//                                        Text("Completion rate")
//                                            .foregroundStyle(Color.white)
//                                            .textDetail()
//                                    }
//                                }
//                                .padding(16)
//                                .frame(maxWidth: .infinity, alignment: .topLeading)
//                                .background(cardBackgroundGradient)
//                                .background(.white.opacity(0.15))
//                                .cornerRadius(16)
//                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
//                                .overlay(
//                                    RoundedRectangle(cornerRadius: 16)
//                                        .inset(by: 1)
//                                        .stroke(.white.opacity(0.15), lineWidth: 1)
//                                )
//                            }
//                        }
//                        .frame(maxWidth:.infinity, alignment:.leading)
                    }
                    .foregroundStyle(Color.white)
                    .padding()
                    .background {
                        if userManager.isSubscriber {
                            GeometryReader { geometry in
                                Color(hex: "#C9C9C9")
                                Image("pro-pattern")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            }
                            .ignoresSafeArea(.all)
                        } else {
                            Color.surface
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius:16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
                }
                
                FadeInView(delay: 0.5) {
                    HStack(alignment:.bottom) {
                        VStack(alignment:.leading) {
                            Image("peapod-plus-mark")
                            
                            Text(favoriteDayName)
                                .foregroundStyle(Color.white)
                                .titleCondensed()
                                .multilineTextAlignment(.center)
                            
                            Text("Favorite day to listen")
                                .foregroundStyle(Color.white)
                                .textDetail()
                        }
                        .frame(maxWidth:.infinity,alignment:.leading)
                        
                        // Weekly listening chart
                        HStack(alignment: .bottom, spacing: 16) {
                            ForEach(weeklyData, id: \.dayOfWeek) { dayData in
                                VStack(spacing: 4) {
                                    // Bar
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white)
                                        .frame(width: 6, height: max(2, dayData.percentage * 40)) // Min height of 4, max of 40
                                        .animation(.easeInOut(duration: 0.8).delay(0.1 * Double(dayData.dayOfWeek)), value: dayData.percentage)
                                        .shadow(color: dayData.percentage == 1.0 ? Color.white : Color.clear, radius: 16)
                                    
                                    // Day label
                                    Text(dayData.dayAbbreviation)
                                        .foregroundStyle(Color.white)
                                        .textDetail()
                                }
                                .opacity(dayData.percentage == 1.0 ? 1.0 : 0.5)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .foregroundStyle(Color.white)
                    .padding()
                    .background {
                        LinearGradient(
                            stops: [
                                Gradient.Stop(color: Color(red: 1, green: 0.42, blue: 0.42), location: 0.00),
                                Gradient.Stop(color: Color(red: 0.2, green: 0.2, blue: 0.2), location: 1.00),
                            ],
                            startPoint: UnitPoint(x: 0, y: 0.5),
                            endPoint: UnitPoint(x: 1, y: 0.5)
                        )
                        Image("Noise")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius:16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
                }
                
                FadeInView(delay: 0.5) {
                    VStack(alignment:.leading) {
                        Image("peapod-plus-mark")
                        
                        FadeInView(delay: 0.6) {
                            Text("My Top Podcasts")
                                .foregroundStyle(Color.white)
                                .titleCondensed()
                                .multilineTextAlignment(.center)
                        }
                        
                        FadeInView(delay: 0.7) {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(reordered, id: \.1.id) { (index, podcast) in
                                    ZStack(alignment:.bottom) {
                                        ArtworkView(url:podcast.image ?? "", size: index == 0 ? 128 : 64, cornerRadius: index == 0 ? 16 : 8)
                                            .if(index == 0, transform: {
                                                $0.background(
                                                    Image("rays")
                                                        .rotationEffect(Angle(degrees: isSpinning ? 360 : 0))
                                                        .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: isSpinning)
                                                )
                                            })
                                        
                                        Spacer()
                                        
                                        Text("\(podcast.formattedPlayedHours)")
                                            .foregroundStyle(Color.black)
                                            .textDetailEmphasis()
                                            .padding(.vertical, 3)
                                            .padding(.horizontal, 8)
                                            .background(Color.white)
                                            .clipShape(Capsule())
                                            .offset(y:12)
                                    }
                                    .zIndex(index == 0 ? 0 : 1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .foregroundStyle(Color.white)
                    .padding([.horizontal,.top]).padding(.bottom,44)
                    .background {
                        if let winner = reordered.first(where: { $0.0 == 0 }) {
                            ArtworkView(url: winner.1.image ?? "", size: 500, cornerRadius: 0)
                                .blur(radius: 128)
                        }
                        Image("Noise")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius:16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
                }
                
                if topPlayedEpisodes.count > 1 {
                    FadeInView(delay: 0.5) {
                        VStack(alignment:.leading) {
                            Image("peapod-plus-mark")
                            
                            FadeInView(delay: 0.6) {
                                Text("Repeat Listener")
                                    .foregroundStyle(Color.white)
                                    .titleCondensed()
                                    .multilineTextAlignment(.center)
                                
                                Text("You've come back to these episodes.")
                                    .foregroundStyle(Color.white)
                                    .textDetail()
                            }
                            
                            FadeInView(delay: 0.7) {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(topPlayedEpisodes, id: \.self) { episode in
                                        Text("\(episode.title ?? "")")
                                    }
                                }
                            }
                        }
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .foregroundStyle(Color.white)
                        .padding([.horizontal,.top]).padding(.bottom,44)
                        .background {
                            if let winner = reordered.first(where: { $0.0 == 0 }) {
                                ArtworkView(url: winner.1.image ?? "", size: 500, cornerRadius: 0)
                                    .blur(radius: 128)
                            }
                            Image("Noise")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .opacity(0.5)
                        }
                        .clipShape(RoundedRectangle(cornerRadius:16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
                    }
                }
                
                if let longestEpisode = longestEpisodes.first {
                    FadeInView(delay: 0.5) {
                        VStack(alignment:.leading) {
                            HStack(alignment:.top) {
                                let duration = Int(longestEpisode.actualDuration)
                                Image("peapod-plus-mark")
                                Spacer()
                                
                                FadeInView(delay: 0.8) {
                                    Text("\(formatDuration(seconds: duration))")
                                        .foregroundStyle(Color.black)
                                        .textDetailEmphasis()
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 8)
                                        .background(Color.white)
                                        .clipShape(Capsule())
                                }
                            }
                            
                            FadeInView(delay: 0.6) {
                                Text("Longest Completed Episode")
                                    .foregroundStyle(Color.white)
                                    .titleCondensed()
                                    .multilineTextAlignment(.center)
                            }
                            
                            FadeInView(delay: 0.7) {
                                HStack {
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
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.border, lineWidth: 1))
                    }
                }
            }
            
            Spacer().frame(height:64)
        }
        .contentMargins(.horizontal,16, for:.scrollContent)
        .maskEdge(.top)
        .maskEdge(.bottom)
        .onAppear {
            isSpinning = true
        }
        .task {
            await loadStatistics()
            await loadFavoriteDay()
        }
    }
    
    // MARK: - Statistics Loading
    private func loadStatistics() async {
        let context = PersistenceController.shared.container.viewContext
        
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
            print("Error loading statistics: \(error)")
            // Keep default zero values on error
        }
    }
    
    private func loadFavoriteDay() async {
        let context = PersistenceController.shared.container.viewContext
        
        do {
            // Load weekly data
            let weeklyListeningData = try Episode.getWeeklyListeningData(in: context)
            
            // Find favorite day
            if let (dayOfWeek, count) = try Episode.mostPopularListeningDay(in: context) {
                let dayName = Episode.dayName(from: dayOfWeek)
                
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
            print("Error loading favorite day: \(error)")
            DispatchQueue.main.async {
                self.favoriteDayName = "Unable to load"
            }
        }
    }
}
