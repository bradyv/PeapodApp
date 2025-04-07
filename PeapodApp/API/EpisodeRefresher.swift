//
//  EpisodeRefresher.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-04.
//

import Foundation
import CoreData
import FeedKit

class EpisodeRefresher {
    static func refreshPodcastEpisodes(for podcast: Podcast, context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        guard let feedUrl = podcast.feedUrl, let url = URL(string: feedUrl) else {
            completion?()
            return
        }

        FeedParser(URL: url).parseAsync { result in
            switch result {
            case .success(let feed):
                if let rss = feed.rssFeed {
                    context.perform {
                        let existingIDs = Set((podcast.episode?.compactMap { ($0 as? Episode)?.title }) ?? [])

                        for item in rss.items ?? [] {
                            guard let title = item.title, !existingIDs.contains(title) else { continue }

                            let e = Episode(context: context)
                            e.id = UUID().uuidString
                            e.title = title
                            e.audio = item.enclosure?.attributes?.url
                            e.episodeDescription = item.content?.contentEncoded ?? item.description
                            e.airDate = item.pubDate
                            if let durationString = item.iTunes?.iTunesDuration {
                                e.duration = Double(durationString)
                            }
                            e.episodeImage = item.iTunes?.iTunesImage?.attributes?.href
                            e.podcast = podcast
                            
                            if let podcast = e.podcast, podcast.isSubscribed {
                                e.isQueued = true
                            }
                        }

                        try? context.save()
                        completion?()
                    }
                } else {
                    completion?()
                }
            case .failure:
                completion?()
            }
        }
    }

    static func refreshAllSubscribedPodcasts(context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")

        if let podcasts = try? context.fetch(request) {
            let group = DispatchGroup()

            for podcast in podcasts {
                group.enter()
                refreshPodcastEpisodes(for: podcast, context: context) {
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion?()
            }
        } else {
            completion?()
        }
    }
}
