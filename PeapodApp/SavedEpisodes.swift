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
        ScrollView {
            Spacer().frame(height:24)
            FadeInView(delay: 0.2) {
                Text("Saved Episodes")
                    .titleSerif()
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .padding(.leading).padding(.top,24)
            }
            
            if saved.isEmpty {
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
                        Text("No saved episodes")
                            .titleCondensed()
                        
                        Text("Tap \(Image(systemName:"bookmark")) on any episode you'd like to save for later.")
                            .textBody()
                    }
                }
            } else {
                ForEach(saved, id: \.id) { episode in
                    FadeInView(delay: 0.3) {
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
        }
        .disabled(saved.isEmpty)
    }
}
