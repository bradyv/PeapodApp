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
            Text("Starred")
                .titleSerif()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(saved, id: \.id) { episode in
                EpisodeItem(episode: episode)
                    .lineLimit(3)
                    .padding(.bottom, 24)
                    .onTapGesture {
                        selectedEpisode = episode
                    }
            }
            .sheet(item: $selectedEpisode) { episode in
                EpisodeView(episode: episode)
                    .modifier(PPSheet())
            }
        }
        .padding()
        .ignoresSafeArea(edges: .all)
    }
}
