//
//  Utilities.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-21.
//

import Foundation
import CoreData
import CloudKit

func runDeduplicationOnceIfNeeded(context: NSManagedObjectContext) {
    let versionKey = "com.bradyv.Peapod.Dev.didDeduplicatePodcasts.v1"
    // Uncomment this line if you want to skip if already run
    // if UserDefaults.standard.bool(forKey: versionKey) {
    //     return
    // }

    deduplicatePodcasts(context: context)
    UserDefaults.standard.set(true, forKey: versionKey)
}

// Updated deduplication function for the new model
func mergeDuplicateEpisodes(context: NSManagedObjectContext) {
    // Ensure we're using a background context
    let backgroundContext = context.concurrencyType == .mainQueueConcurrencyType ?
        PersistenceController.shared.container.newBackgroundContext() : context
    
    backgroundContext.perform {
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()

        do {
            let episodes = try backgroundContext.fetch(request)
            print("🔍 Checking \(episodes.count) episodes for duplicates")

            var episodesByGUID: [String: [Episode]] = [:]

            for episode in episodes {
                if let guid = episode.guid {
                    episodesByGUID[guid, default: []].append(episode)
                }
            }

            var duplicatesFound = 0

            for (_, duplicates) in episodesByGUID {
                if duplicates.count > 1 {
                    // Keep the newest one based on airDate
                    let sorted = duplicates.sorted {
                        ($0.airDate ?? Date.distantPast) > ($1.airDate ?? Date.distantPast)
                    }

                    guard let keeper = sorted.first else { continue }
                    let toDelete = sorted.dropFirst()

                    for duplicate in toDelete {
                        // Transfer important flags using the new boolean system
                        if duplicate.isQueued {
                            keeper.isQueued = true
                            keeper.queuePosition = max(keeper.queuePosition, duplicate.queuePosition)
                        }
                        
                        if duplicate.isPlayed {
                            keeper.isPlayed = true
                            keeper.playedDate = max(keeper.playedDate ?? Date.distantPast, duplicate.playedDate ?? Date.distantPast)
                        }
                        
                        if duplicate.isFav {
                            keeper.isFav = true
                            keeper.favDate = max(keeper.favDate ?? Date.distantPast, duplicate.favDate ?? Date.distantPast)
                        }

                        // Transfer playback position
                        if duplicate.playbackPosition > 0 {
                            keeper.playbackPosition = max(keeper.playbackPosition, duplicate.playbackPosition)
                        }

                        backgroundContext.delete(duplicate)
                        duplicatesFound += 1
                    }
                }
            }

            // Save on background context
            if backgroundContext.hasChanges {
                try backgroundContext.save()
                
                // If we created a new background context, merge changes to main context
                if backgroundContext !== context {
                    DispatchQueue.main.async {
                        PersistenceController.shared.container.viewContext.mergeChanges(
                            fromContextDidSave: Notification(name: .NSManagedObjectContextDidSave)
                        )
                    }
                }
            }
            
            LogManager.shared.info("✅ Merged and deleted \(duplicatesFound) duplicate episode(s)")
        } catch {
            LogManager.shared.error("⚠️ Failed merging duplicates: \(error)")
        }
    }
}

// Updated deduplication for podcasts with new episode relationship
func deduplicatePodcasts(context: NSManagedObjectContext) {
    // Ensure we're using a background context
    let backgroundContext = context.concurrencyType == .mainQueueConcurrencyType ?
        PersistenceController.shared.container.newBackgroundContext() : context
    
    backgroundContext.perform {
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()

        do {
            let podcasts = try backgroundContext.fetch(request)
            
            // Group by normalized URL instead of exact match
            let groupedByNormalizedUrl = Dictionary(grouping: podcasts) { podcast in
                podcast.feedUrl?.normalizeURL() ?? UUID().uuidString
            }

            for (normalizedUrl, group) in groupedByNormalizedUrl {
                guard group.count > 1 else { continue }

                // Prefer the one that is subscribed, then newest
                let primary = group.first(where: { $0.isSubscribed }) ??
                             group.max(by: { ($0.objectID.description) < ($1.objectID.description) })!

                // Update primary with normalized URL
                primary.feedUrl = normalizedUrl

                for duplicate in group {
                    if duplicate == primary { continue }

                    // Merge metadata (prefer non-nil values)
                    if primary.title == nil { primary.title = duplicate.title }
                    if primary.author == nil { primary.author = duplicate.author }
                    if primary.image == nil { primary.image = duplicate.image }
                    if primary.podcastDescription == nil { primary.podcastDescription = duplicate.podcastDescription }

                    // Reassign episodes using podcastId
                    let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                    episodeRequest.predicate = NSPredicate(format: "podcastId == %@", duplicate.id ?? "")
                    
                    if let episodes = try? backgroundContext.fetch(episodeRequest) {
                        for episode in episodes {
                            episode.podcastId = primary.id
                        }
                    }

                    backgroundContext.delete(duplicate)
                }
            }

            // Save on background context
            if backgroundContext.hasChanges {
                try backgroundContext.save()
                
                // If we created a new background context, merge changes to main context
                if backgroundContext !== context {
                    DispatchQueue.main.async {
                        PersistenceController.shared.container.viewContext.mergeChanges(
                            fromContextDidSave: Notification(name: .NSManagedObjectContextDidSave)
                        )
                    }
                }
            }
            
            LogManager.shared.info("✅ Enhanced podcast deduplication complete.")
        } catch {
            LogManager.shared.error("⚠️ Failed to deduplicate podcasts: \(error)")
        }
    }
}

// MARK: - Simple & Reliable Sync Store Wiper
func quickWipeSyncData() {
    print("🧹 Wiping sync data...")
    
    let context = PersistenceController.shared.container.viewContext
    
    // Delete all synced entities from Core Data
    let entityNames = ["Podcast", "User", "Playback"]
    
    for entityName in entityNames {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try context.execute(deleteRequest)
            print("🗑️ Deleted all \(entityName) records")
        } catch {
            print("❌ Error deleting \(entityName): \(error)")
        }
    }
    
    // Save the context to trigger CloudKit sync
    do {
        try context.save()
        print("✅ Sync data wipe complete!")
        print("📤 CloudKit will sync the deletions")
    } catch {
        print("❌ Error saving context: \(error)")
    }
}

// MARK: - Complete Store Reset (Nuclear Option)

func completeStoreReset() {
    print("💥 COMPLETE STORE RESET - This will restart the app!")
    
    let container = PersistenceController.shared.container
    let coordinator = container.persistentStoreCoordinator
    
    // Remove all stores
    for store in coordinator.persistentStores {
        do {
            try coordinator.remove(store)
            
            // Delete the store files
            if let storeURL = store.url {
                let fileManager = FileManager.default
                try? fileManager.removeItem(at: storeURL)
                try? fileManager.removeItem(at: storeURL.appendingPathExtension("wal"))
                try? fileManager.removeItem(at: storeURL.appendingPathExtension("shm"))
                print("🗑️ Deleted store: \(storeURL.lastPathComponent)")
            }
        } catch {
            print("❌ Error removing store: \(error)")
        }
    }
    
    print("💥 Complete reset done - app needs restart!")
    print("🔄 Force quit and relaunch the app")
}

// MARK: - CloudKit Dashboard Reset (Manual Instructions)

func printCloudKitResetInstructions() {
    print("""
    
    🌩️ TO MANUALLY RESET CLOUDKIT DATA:
    
    1. Go to: https://icloud.developer.apple.com
    2. Select your app: iCloud.com.bradyv.PeapodApp  
    3. Click "Development" environment
    4. Go to "Data" tab
    5. Delete record types one by one:
       - CD_Podcast  
       - CD_User
       - CD_Playback
    6. Or use "Reset Development Environment" button
    
    ⚠️ This will delete ALL CloudKit data!
    
    """)
}

// MARK: - Recommended Testing Workflow

func resetForTesting() {
    print("🧪 Resetting for fresh testing...")
    
    // Option 1: Quick wipe (keeps app running)
    quickWipeSyncData()
    
    // Option 2: If you want complete reset (requires app restart)
    // completeStoreReset()
    
    // Option 3: Manual CloudKit reset instructions
    // printCloudKitResetInstructions()
}

// MARK: - Debug Info

func printCurrentSyncData() {
    let context = PersistenceController.shared.container.viewContext
    
    print("\n📊 CURRENT SYNC DATA:")
    print("====================")
    
    let entityNames = ["Podcast", "User", "Playback"]
    
    for entityName in entityNames {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let count = (try? context.count(for: request)) ?? 0
        print("📋 \(entityName): \(count) records")
    }
    
    print("====================\n")
}
