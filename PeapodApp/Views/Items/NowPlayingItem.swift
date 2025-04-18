//
//  NowPlayingItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-18.
//

import SwiftUI

struct NowPlayingItem: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "nowPlayingItem == YES"),
        animation: .default
    ) var nowPlaying: FetchedResults<Episode>

    var body: some View {
        if let episode = nowPlaying.first {
            QueueItem(episode: episode)
        }
    }
}
