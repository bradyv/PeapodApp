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
    @State var degreesRotating = 0.0
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    @State private var isSpinning = false
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
                            ZStack(alignment:.bottom) {
                                if index == 0 {
                                    ZStack {
                                        // Background spinning rays
                                        Image("rays")
                                            .opacity(0.05)
                                            .rotationEffect(Angle(degrees: isSpinning ? 360 : 0))
                                            .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: isSpinning)
                                        
                                        // Blurred background version of the image (larger)
                                        KFImage(URL(string: podcast.image ?? ""))
                                            .resizable()
                                            .frame(width: 128, height: 128)
                                            .aspectRatio(1, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 20))
                                            .blur(radius: 64)
                                            .opacity(0.3)
                                        
                                        // Main crisp image on top
                                        KFImage(URL(string: podcast.image ?? ""))
                                            .resizable()
                                            .frame(width: 128, height: 128)
                                            .aspectRatio(1, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                                    }
                                } else {
                                    // Regular image for non-winners
                                    KFImage(URL(string: podcast.image ?? ""))
                                        .resizable()
                                        .frame(width: 64, height: 64)
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                                }
                                
                                Spacer()
                                
                                Text("\(podcast.formattedPlayedHours)")
                                    .foregroundStyle(Color.background)
                                    .textMini()
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 8)
                                    .background(Color.heading)
                                    .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.background, lineWidth: 2))
                            }
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
        .onAppear {
            isSpinning = true
        }
    }
}
