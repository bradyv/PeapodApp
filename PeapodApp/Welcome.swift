//
//  Welcome.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-06.
//

import SwiftUI
import Kingfisher

struct Welcome: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var fetcher: PodcastFetcher
    
    var body: some View {
        TopPodcasts { podcast in
            Task {
                do {
                    let _ = try await FeedLoader.loadAndCreatePodcast(from: podcast.feedUrl, in: context)
                    // Optional: trigger UI feedback (toast, alert, etc.)
                } catch {
                    print("❌ Subscription failed:", error.localizedDescription)
                }
            }
        }
    }
}
