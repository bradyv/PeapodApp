//
//  ActivityView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-10.
//

import SwiftUI

struct ActivityView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Episode.playedDate, ascending: false)],
        predicate: NSPredicate(format: "isPlayed == YES"),
        animation: .interactiveSpring()
    )
    var played: FetchedResults<Episode>
    @State private var selectedEpisode: Episode? = nil
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:24)
            FadeInView(delay: 0.2) {
                Text("Listening Activity")
                    .titleSerif()
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .padding(.leading).padding(.top,24)
            }
            
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
                ForEach(played, id: \.id) { episode in
                    FadeInView(delay: 0.3) {
                        EpisodeItem(episode: episode)
                            .lineLimit(3)
                            .padding(.bottom, 24)
                            .padding(.horizontal)
                            .onTapGesture {
                                selectedEpisode = episode
                            }
                    }
                }
                .sheet(item: $selectedEpisode) { episode in
                    EpisodeView(episode: episode)
                        .modifier(PPSheet())
                }
            }
        }
        .disabled(played.isEmpty)
    }
}
