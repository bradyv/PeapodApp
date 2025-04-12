//
//  CloudKitMigrator.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-12.
//

import CoreData

enum CloudKitMigrator {
    static func migrateSubscribedContentIfNeeded(context: NSManagedObjectContext) {
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")

        do {
            let subscribedPodcasts = try context.fetch(request)
            var modifiedCount = 0

            for podcast in subscribedPodcasts {
                // Touch the podcast object (e.g., update a dummy field)
                podcast.title = podcast.title // Triggers change tracking

                // Migrate related episodes
                if let episodes = podcast.episode as? Set<Episode> {
                    for episode in episodes {
                        episode.title = episode.title // Triggers change tracking
                        modifiedCount += 1
                    }
                }
            }

            if context.hasChanges {
                try context.save()
                print("✅ CloudKitMigrator: Migrated \(subscribedPodcasts.count) podcasts and \(modifiedCount) episodes")
            } else {
                print("ℹ️ CloudKitMigrator: No changes to migrate")
            }

        } catch {
            print("❌ CloudKitMigrator failed: \(error)")
        }
    }
}

