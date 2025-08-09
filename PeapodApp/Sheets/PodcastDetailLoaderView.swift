//
//  PodcastDetailLoaderView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import FeedKit

struct PodcastDetailLoaderView: View {
    let feedUrl: String
    @Environment(\.managedObjectContext) private var context
    @State private var loadedPodcast: Podcast? = nil

    var body: some View {
        Group {
            if let podcast = loadedPodcast {
                PodcastDetailView(feedUrl: podcast.feedUrl ?? "")
            } else {
                VStack {
                    ProgressView("Loading...")
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
        .onAppear {
            PodcastLoader.loadFeed(from: feedUrl, context: context) { podcast in
                self.loadedPodcast = podcast
            }
        }
    }
}
