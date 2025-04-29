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
                        if podcast.image == nil {
                            podcast.image = rss.image?.url ??
                                            rss.iTunes?.iTunesImage?.attributes?.href ??
                                            rss.items?.first?.iTunes?.iTunesImage?.attributes?.href
                        }

                        if podcast.podcastDescription == nil {
                            podcast.podcastDescription = rss.description ??
                                                          rss.iTunes?.iTunesSummary ??
                                                          rss.items?.first?.iTunes?.iTunesSummary ??
                                                          rss.items?.first?.description
                        }

                        // 🚀 Instead of fetching ALL episodes, let's build GUID list first
                        var guids: [String] = []
                        var titleDateKeys: [String] = []

                        for item in rss.items ?? [] {
                            if let guid = item.guid?.value {
                                guids.append(guid)
                            } else if let title = item.title, let airDate = item.pubDate {
                                let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                                titleDateKeys.append(key)
                            }
                        }

                        var existingEpisodesByGUID: [String: Episode] = [:]
                        var existingEpisodesByTitleAndDate: [String: Episode] = [:]

                        // 🚀 Fetch existing episodes by GUID only
                        if !guids.isEmpty {
                            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                            fetchRequest.predicate = NSPredicate(format: "podcast == %@ AND guid IN %@", podcast, guids)
                            if let results = try? context.fetch(fetchRequest) {
                                for episode in results {
                                    if let guid = episode.guid {
                                        existingEpisodesByGUID[guid] = episode
                                    }
                                }
                            }
                        }

                        // 🚀 Fetch existing episodes by Title+AirDate if no GUID
                        if !titleDateKeys.isEmpty {
                            let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                            fetchRequest.predicate = NSPredicate(format: "podcast == %@ AND title != nil AND airDate != nil", podcast)
                            if let results = try? context.fetch(fetchRequest) {
                                for episode in results {
                                    if let title = episode.title, let airDate = episode.airDate {
                                        let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                                        existingEpisodesByTitleAndDate[key] = episode
                                    }
                                }
                            }
                        }

                        for item in rss.items ?? [] {
                            guard let title = item.title else { continue }

                            let guid = item.guid?.value
                            let airDate = item.pubDate

                            var existingEpisode: Episode?

                            if let guid = guid {
                                existingEpisode = existingEpisodesByGUID[guid]
                            }
                            if existingEpisode == nil, let airDate = airDate {
                                let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                                existingEpisode = existingEpisodesByTitleAndDate[key]
                            }

                            let episode = existingEpisode ?? Episode(context: context)

                            if existingEpisode == nil {
                                episode.id = UUID().uuidString
                                episode.podcast = podcast
                            }

                            episode.guid = guid
                            episode.title = title
                            episode.audio = item.enclosure?.attributes?.url
                            episode.episodeDescription = item.content?.contentEncoded ?? item.iTunes?.iTunesSummary ?? item.description
                            episode.airDate = airDate
                            if let durationString = item.iTunes?.iTunesDuration {
                                episode.duration = Double(durationString)
                            }
                            episode.episodeImage = item.iTunes?.iTunesImage?.attributes?.href ?? podcast.image

                            if existingEpisode == nil, podcast.isSubscribed {
                                print("📣 New episode detected: \(episode.title ?? "Unknown") — sending notification")
                                sendNewEpisodeNotification(for: episode)
                                
                                toggleQueued(episode)
                            } else if existingEpisode != nil {
                                print("🧹 Existing episode updated: \(episode.title ?? "Unknown") — no notification")
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
        // 🚀 Create a new background context
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        backgroundContext.perform {
            let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
            request.predicate = NSPredicate(format: "isSubscribed == YES")

            if let podcasts = try? backgroundContext.fetch(request) {
                let group = DispatchGroup()

                for podcast in podcasts {
                    group.enter()
                    refreshPodcastEpisodes(for: podcast, context: backgroundContext) {
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    do {
                        try backgroundContext.save()
                        print("✅ Background context saved after refreshing subscribed podcasts")
                    } catch {
                        print("❌ Failed to save background context: \(error)")
                    }
                    completion?()
                }
            } else {
                completion?()
            }
        }
    }
}
