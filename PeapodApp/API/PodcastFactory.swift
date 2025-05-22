//
//  PodcastFactory.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-24.
//

import CoreData

func fetchOrCreatePodcast(feedUrl: String, context: NSManagedObjectContext, title: String? = nil, author: String? = nil) -> Podcast {
    return PodcastManager.fetchOrCreatePodcast(feedUrl: feedUrl, context: context, title: title, author: author)
}
