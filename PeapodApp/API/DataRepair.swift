//
//  DataRepair.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-24.
//

import Foundation
import CoreData

func deduplicatePodcasts(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()

    do {
        let podcasts = try context.fetch(request)
        let groupedByFeedUrl = Dictionary(grouping: podcasts, by: { $0.feedUrl ?? UUID().uuidString })

        for (feedUrl, group) in groupedByFeedUrl {
            guard group.count > 1 else { continue }

            // Prefer the one that is subscribed
            let primary = group.first(where: { $0.isSubscribed }) ?? group.first!

            for duplicate in group {
                if duplicate == primary { continue }

                // Reassign episodes
                for episode in duplicate.episode ?? [] {
                    (episode as? Episode)?.podcast = primary
                }

                context.delete(duplicate)
            }
        }

        try context.save()
        print("✅ Podcast deduplication complete.")
    } catch {
        print("❌ Failed to deduplicate podcasts: \(error)")
    }
}

func runDeduplicationOnceIfNeeded(context: NSManagedObjectContext) {
    let versionKey = "com.bradyv.Peapod.Dev.didDeduplicatePodcasts.v1"
    if UserDefaults.standard.bool(forKey: versionKey) {
        return
    }

    deduplicatePodcasts(context: context)
    UserDefaults.standard.set(true, forKey: versionKey)
}
