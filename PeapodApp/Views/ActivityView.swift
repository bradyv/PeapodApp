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
    @FetchRequest(
        fetchRequest: Episode.recentlyPlayedRequest(limit: 5),
        animation: .interactiveSpring()
    )
    var played: FetchedResults<Episode>
    
    @FetchRequest(
        fetchRequest: Podcast.topPlayedRequest(),
        animation: .default
    )
    var topPodcasts: FetchedResults<Podcast>
    @State private var selectedEpisode: Episode? = nil
    @State private var selectedPodcast: Podcast? = nil
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    var namespace: Namespace.ID
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:52)
            Text("My Activity")
                .titleSerif()
                .frame(maxWidth:.infinity, alignment:.leading)
                .padding(.horizontal)
            
            if !played.isEmpty {
                FadeInView(delay: 0.2) {
                    Text("Top Shows")
                        .headerSection()
                        .frame(maxWidth:.infinity, alignment: .leading)
                        .padding(.leading).padding(.top,16)
                }
                
                let podiumOrder = [1, 0, 2]
                let reordered: [(Int, Podcast)] = podiumOrder.compactMap { index in
                    guard index < topPodcasts.count else { return nil }
                    return (index, topPodcasts[index])
                }
                
                FadeInView(delay: 0.3) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(reordered, id: \.1.id) { (index, podcast) in
                            VStack {
                                let image = KFImage(URL(string: podcast.image ?? ""))
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                                
                                let styledImage = image
                                    .if(index == 0, transform: {
                                        $0.shadow(color: Color.tint(for: podcast, opacity: 0.5), radius: 32, x: 0, y: 0)
                                    })
                                
                                styledImage
                                
                                Text(podcast.formattedPlayedHours)
                                    .textBody()
                            }
                            .if(index != 0, transform: {
                                $0.scaleEffect(0.75)
                            })
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            if played.isEmpty {
                FadeInView(delay: 0.5) {
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
                }
            } else {
                FadeInView(delay: 0.4) {
                    Text("Listening Activity")
                        .headerSection()
                        .frame(maxWidth:.infinity, alignment: .leading)
                        .padding(.leading).padding(.top,24)
                }
                
                VStack {
                    ForEach(played, id: \.id) { episode in
                        FadeInView(delay: 0.5) {
                            EpisodeItem(episode: episode, namespace: namespace)
                                .lineLimit(3)
                                .padding(.bottom, 24)
                                .padding(.horizontal)
                                .matchedTransitionSource(id: episode.id, in: namespace)
                        }
                    }
                }
            }
        }
        .maskEdge(.top)
        .maskEdge(.bottom)
    }
}

extension Podcast {
    static func topPlayedRequest() -> NSFetchRequest<Podcast> {
        let request = NSFetchRequest<Podcast>(entityName: "Podcast")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Podcast.playedSeconds, ascending: false)]
        request.fetchLimit = 3
        return request
    }
    
    static func totalPlayedDuration(in context: NSManagedObjectContext) async throws -> Double {
        let request = NSFetchRequest<NSDictionary>(entityName: "Podcast")
        request.resultType = .dictionaryResultType

        let sumExpression = NSExpressionDescription()
        sumExpression.name = "totalPlayedDuration"
        sumExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "playedSeconds")])
        sumExpression.expressionResultType = .doubleAttributeType

        request.propertiesToFetch = [sumExpression]

        let results = try context.fetch(request)
        let total = results.first?["totalPlayedDuration"] as? Double ?? 0.0
        return total
    }
    
    static func totalSubscribedCount(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSNumber>(entityName: "Podcast")
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        request.resultType = .countResultType

        return try context.count(for: request)
    }

    static func totalPlayCount(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSDictionary>(entityName: "Podcast")
        request.resultType = .dictionaryResultType

        let sumExpression = NSExpressionDescription()
        sumExpression.name = "totalPlayCount"
        sumExpression.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "playCount")])
        sumExpression.expressionResultType = .integer32AttributeType

        request.propertiesToFetch = [sumExpression]

        let results = try context.fetch(request)
        return results.first?["totalPlayCount"] as? Int ?? 0
    }
    
    var formattedPlayedHours: String {
        let hours = playedSeconds / 3600
        let rounded = (hours * 10).rounded() / 10  // round to 1 decimal place

        if rounded < 0.1 {
            return "Less than 1 hour"
        }

        if rounded == floor(rounded) {
            let whole = Int(rounded)
            return "\(whole) " + (whole == 1 ? "hour" : "hours")
        } else {
            return String(format: "%.1f hours", rounded)
        }
    }
}

extension Episode {
    static func recentlyPlayedRequest(limit: Int = 5) -> NSFetchRequest<Episode> {
        let request = NSFetchRequest<Episode>(entityName: "Episode")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.playedDate, ascending: false)]
        request.predicate = NSPredicate(format: "isPlayed == YES")
        request.fetchLimit = limit
        return request
    }
}
