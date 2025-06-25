//
//  PodcastFactory.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-24.
//

import CoreData

func fetchOrCreatePodcast(feedUrl: String, context: NSManagedObjectContext, title: String? = nil, author: String? = nil) -> Podcast {
    let normalizedUrl = feedUrl.normalizeURL()
    
    let request = Podcast.fetchRequest()
    request.predicate = NSPredicate(format: "feedUrl == %@", normalizedUrl)
    request.fetchLimit = 1

    if let existing = try? context.fetch(request).first {
        return existing
    } else {
        let podcast = Podcast(context: context)
        podcast.feedUrl = normalizedUrl
        podcast.id = UUID().uuidString
        podcast.title = title
        podcast.author = author
        return podcast
    }
}

