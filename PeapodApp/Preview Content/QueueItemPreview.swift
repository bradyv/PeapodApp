//
//  QueueItemPreview.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import CoreData

struct QueueItem_Previews: PreviewProvider {
    static var previews: some View {
        let context = PreviewPersistenceController.makeContainer().viewContext
        let episode = createPreviewEpisode(in: context)

        return QueueItem(episode: episode)
            .environment(\.managedObjectContext, context)
    }

    static func createPreviewEpisode(in context: NSManagedObjectContext) -> Episode {
        let podcast = Podcast(context: context)
        podcast.id = "1"
        podcast.title = "The Conference Call"
        podcast.author = "#business"
        podcast.image = "https://bradyv.github.io/bvfeed.github.io/conf-call.png"
        podcast.podcastDescription = "Join the #business team for their weekly all-hands."
        podcast.feedUrl = "https://bradyv.github.io/bvfeed.github.io/feed.xml"
        podcast.isSubscribed = true
        
        let episode = Episode(context: context)
        episode.id = "01"
        episode.title = "Pilot: Dave Was Fired"
        episode.podcast = podcast
        episode.duration = 1234
        episode.audio = "https://pdst.fm/e/traffic.megaphone.fm/GLT6389139975.mp3?updated=1743108043"
        episode.episodeImage = "https://bradyv.github.io/bvfeed.github.io/conf-call-episode.png"
        episode.airDate = Date.now
        episode.isQueued = true
        episode.hasBeenSeen = true

        return episode
    }
}
