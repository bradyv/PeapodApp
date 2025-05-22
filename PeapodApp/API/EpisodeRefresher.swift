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
    // Keep the lock mechanism for backwards compatibility
    static let podcastRefreshLocks = NSMapTable<NSString, NSLock>.strongToStrongObjects()
    
    // Delegate to the new EpisodeManager
    static func refreshPodcastEpisodes(for podcast: Podcast, context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        EpisodeManager.refreshPodcastEpisodes(for: podcast, context: context, completion: completion)
    }

    static func refreshAllSubscribedPodcasts(context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        EpisodeManager.refreshAllSubscribedPodcasts(context: context, completion: completion)
    }
}
