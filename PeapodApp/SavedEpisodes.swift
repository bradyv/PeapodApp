//
//  SavedEpisodes.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct SavedEpisodes: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.id)],
        predicate: NSPredicate(format: "isSaved == YES"),
        animation: .interactiveSpring()
    )
    var saved: FetchedResults<Episode>
    @State private var selectedEpisode: Episode? = nil
    
    var body: some View {
        if saved.isEmpty {
            ZStack {
                ScrollView {
                    Spacer().frame(height:24)
                    Text("Starred")
                        .titleSerif()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading).padding(.top,24)
                    
                    EmptyEpisodeItem()
                        .opacity(0.03)
                    EmptyEpisodeItem()
                        .opacity(0.03)
                    EmptyEpisodeItem()
                        .opacity(0.03)
                    EmptyEpisodeItem()
                        .opacity(0.03)
                    EmptyEpisodeItem()
                        .opacity(0.03)
                }
                .disabled(true)
                .mask(
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                   startPoint: .top, endPoint: .init(x: 0.5, y: 0.8))
                )
                
                VStack {
                    Text("No starred episodes")
                        .titleCondensed()
                    
                    Text("Tap \(Image(systemName:"star")) on any episode you'd like to save for later.")
                        .textBody()
                }
                .frame(maxWidth:.infinity, maxHeight:.infinity)
            }
        } else {
            ScrollView {
                Spacer().frame(height:24)
                Text("Starred")
                    .titleSerif()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading).padding(.top,24)
                
                ForEach(Array(saved.enumerated()), id: \.1.id) { index, episode in
                    FadeInView(delay: Double(index) * 0.2) {
                        EpisodeItem(episode: episode, savedView:true)
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
            .maskEdge(.bottom)
            .ignoresSafeArea(edges: .all)
        }
    }
}
