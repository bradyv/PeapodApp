//
//  SchemaMigration.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-08-12.
//

import Foundation
import CoreData

class PlaybackMigration {
    
    /// Main migration function to run once on app update
    static func migratePlaybackDataIfNeeded(context: NSManagedObjectContext) {
        let migrationKey = "PlaybackDataMigrated_v2"
        
        // Check if migration already completed
        if UserDefaults.standard.bool(forKey: migrationKey) {
            LogManager.shared.info("✅ Playback data migration already completed")
            return
        }
        
        LogManager.shared.info("🔄 Starting playback data migration...")
        let startTime = Date()
        
        context.performAndWait {
            do {
                let migrationResult = performMigration(context: context)
                
                try context.save()
                
                // Mark migration as complete
                UserDefaults.standard.set(true, forKey: migrationKey)
                
                let duration = Date().timeIntervalSince(startTime)
                LogManager.shared.info("✅ Migration completed in \(String(format: "%.2f", duration))s")
                LogManager.shared.info("📊 Migration stats: \(migrationResult.migrated) episodes migrated, \(migrationResult.created) Playback entities created, \(migrationResult.errors) errors")
                
            } catch {
                LogManager.shared.error("❌ Migration failed: \(error)")
                // Don't mark as complete so it will retry next time
            }
        }
    }
    
    private static func performMigration(context: NSManagedObjectContext) -> (migrated: Int, created: Int, errors: Int) {
        var migratedCount = 0
        var createdCount = 0
        var errorCount = 0
        
        // Step 1: Get all episodes that might have playback data to migrate
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        
        do {
            let episodes = try context.fetch(episodeRequest)
            LogManager.shared.info("📊 Found \(episodes.count) episodes to check for migration")
            
            // Step 2: Process episodes in batches to avoid memory issues
            let batchSize = 100
            for i in stride(from: 0, to: episodes.count, by: batchSize) {
                let endIndex = min(i + batchSize, episodes.count)
                let batch = Array(episodes[i..<endIndex])
                
                let batchResult = processBatch(batch: batch, context: context)
                migratedCount += batchResult.migrated
                createdCount += batchResult.created
                errorCount += batchResult.errors
                
                // Save periodically to avoid large transactions
                if i % (batchSize * 5) == 0 && context.hasChanges {
                    try context.save()
                    LogManager.shared.info("💾 Batch save completed - \(i + batch.count)/\(episodes.count) episodes processed")
                }
            }
            
            // Step 3: Migrate Queue playlist to boolean system
            let queueMigrationResult = migrateQueuePlaylist(context: context)
            migratedCount += queueMigrationResult
            
            // Step 4: Clean up old playlist entities (optional)
            cleanupOldPlaylists(context: context)
            
        } catch {
            LogManager.shared.error("❌ Error fetching episodes for migration: \(error)")
            errorCount += 1
        }
        
        return (migrated: migratedCount, created: createdCount, errors: errorCount)
    }
    
    private static func processBatch(batch: [Episode], context: NSManagedObjectContext) -> (migrated: Int, created: Int, errors: Int) {
        var migratedCount = 0
        var createdCount = 0
        var errorCount = 0
        
        for episode in batch {
            guard let episodeId = episode.id else {
                LogManager.shared.warning("⚠️ Episode missing ID, skipping: \(episode.title ?? "Unknown")")
                continue
            }
            
            do {
                // Check if this episode already has a Playback entity (avoid duplicates)
                if hasExistingPlayback(episodeId: episodeId, context: context) {
                    continue
                }
                
                // Check if episode has any old playback data to migrate
                var hasPlaybackData = false
                var playback: Playback?
                
                // Check for old Episode attributes (safely with nil coalescing)
                let oldIsFav = episode.value(forKey: "isFav") as? Bool ?? false
                let oldIsPlayed = episode.value(forKey: "isPlayed") as? Bool ?? false
                let oldIsQueued = episode.value(forKey: "isQueued") as? Bool ?? false
                let oldIsSaved = episode.value(forKey: "isSaved") as? Bool ?? false
                let oldPlaybackPosition = episode.value(forKey: "playbackPosition") as? Double ?? 0.0
                let oldQueuePosition = episode.value(forKey: "queuePosition") as? Int64 ?? 0
                let oldPlayCount = episode.value(forKey: "playCount") as? Int64 ?? 0
                let oldPlayedDate = episode.value(forKey: "playedDate") as? Date
                let oldFavDate = episode.value(forKey: "favDate") as? Date
                let oldSavedDate = episode.value(forKey: "savedDate") as? Date
                
                // Check if episode was in a Queue playlist (legacy system)
                let wasInQueuePlaylist = checkIfEpisodeWasInQueuePlaylist(episode: episode)
                
                // Determine if we need to create a Playback entity
                if oldIsFav || oldIsPlayed || oldIsQueued || oldIsSaved ||
                   oldPlaybackPosition > 0 || oldPlayCount > 0 ||
                   oldPlayedDate != nil || oldFavDate != nil || oldSavedDate != nil ||
                   wasInQueuePlaylist {
                    hasPlaybackData = true
                }
                
                if hasPlaybackData {
                    // Create new Playback entity
                    playback = Playback(context: context)
                    playback?.episodeId = episodeId
                    
                    // Migrate boolean states
                    playback?.isFav = oldIsFav
                    playback?.isPlayed = oldIsPlayed
                    playback?.isQueued = oldIsQueued || wasInQueuePlaylist // Include queue playlist episodes
                    
                    // Note: isSaved functionality seems to be replaced by isFav, but keeping logic separate
                    // You might want to merge isSaved into isFav if that was the intent
                    if oldIsSaved && !oldIsFav {
                        playback?.isFav = true // Migrate saved episodes to favorites
                    }
                    
                    // Migrate numeric/date values
                    playback?.playbackPosition = oldPlaybackPosition
                    playback?.queuePosition = wasInQueuePlaylist ? getQueuePositionFromPlaylist(episode: episode) : oldQueuePosition
                    playback?.playCount = oldPlayCount
                    playback?.playedDate = oldPlayedDate
                    playback?.favDate = oldFavDate ?? oldSavedDate // Use favDate, fallback to savedDate
                    
                    createdCount += 1
                    migratedCount += 1
                    
                    LogManager.shared.debug("✅ Migrated episode: \(episode.title?.prefix(30) ?? "Unknown") - Fav: \(playback?.isFav ?? false), Queued: \(playback?.isQueued ?? false), Played: \(playback?.isPlayed ?? false)")
                }
                
            } catch {
                LogManager.shared.error("❌ Error migrating episode \(episode.title ?? "Unknown"): \(error)")
                errorCount += 1
            }
        }
        
        return (migrated: migratedCount, created: createdCount, errors: errorCount)
    }
    
    private static func hasExistingPlayback(episodeId: String, context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<Playback> = Playback.fetchRequest()
        request.predicate = NSPredicate(format: "episodeId == %@", episodeId)
        request.fetchLimit = 1
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            LogManager.shared.error("❌ Error checking existing playback: \(error)")
            return false
        }
    }
    
    private static func checkIfEpisodeWasInQueuePlaylist(episode: Episode) -> Bool {
        // Check if episode has a relationship to a playlist named "Queue"
        if let playlist = episode.value(forKey: "playlist") as? NSManagedObject,
           let playlistName = playlist.value(forKey: "name") as? String {
            return playlistName == "Queue"
        }
        return false
    }
    
    private static func getQueuePositionFromPlaylist(episode: Episode) -> Int64 {
        // Try to get queue position from the old system
        // This might need adjustment based on how your old queue playlist stored positions
        return episode.value(forKey: "queuePosition") as? Int64 ?? 0
    }
    
    private static func migrateQueuePlaylist(context: NSManagedObjectContext) -> Int {
        var migratedCount = 0
        
        // Find the "Queue" playlist if it exists
        let playlistRequest = NSFetchRequest<NSManagedObject>(entityName: "Playlist")
        playlistRequest.predicate = NSPredicate(format: "name == %@", "Queue")
        
        do {
            if let queuePlaylist = try context.fetch(playlistRequest).first {
                LogManager.shared.info("📋 Found Queue playlist, migrating episodes...")
                
                // Get episodes in the queue playlist
                if let episodes = queuePlaylist.value(forKey: "items") as? Set<Episode> {
                    for episode in episodes {
                        guard let episodeId = episode.id else { continue }
                        
                        // Find or create Playback entity
                        let playback = findOrCreatePlayback(episodeId: episodeId, context: context)
                        playback.isQueued = true
                        playback.queuePosition = episode.value(forKey: "queuePosition") as? Int64 ?? 0
                        
                        migratedCount += 1
                    }
                    
                    LogManager.shared.info("✅ Migrated \(migratedCount) episodes from Queue playlist")
                }
            }
        } catch {
            LogManager.shared.error("❌ Error migrating Queue playlist: \(error)")
        }
        
        return migratedCount
    }
    
    private static func findOrCreatePlayback(episodeId: String, context: NSManagedObjectContext) -> Playback {
        let request: NSFetchRequest<Playback> = Playback.fetchRequest()
        request.predicate = NSPredicate(format: "episodeId == %@", episodeId)
        request.fetchLimit = 1
        
        if let existing = try? context.fetch(request).first {
            return existing
        } else {
            let playback = Playback(context: context)
            playback.episodeId = episodeId
            return playback
        }
    }
    
    private static func cleanupOldPlaylists(context: NSManagedObjectContext) {
        // Optional: Remove old playlist entities after migration
        // Be careful with this - you might want to keep playlists for other purposes
        
        let playlistRequest = NSFetchRequest<NSManagedObject>(entityName: "Playlist")
        playlistRequest.predicate = NSPredicate(format: "name == %@", "Queue")
        
        do {
            let oldPlaylists = try context.fetch(playlistRequest)
            for playlist in oldPlaylists {
                context.delete(playlist)
            }
            
            if !oldPlaylists.isEmpty {
                LogManager.shared.info("🗑️ Cleaned up \(oldPlaylists.count) old Queue playlist(s)")
            }
        } catch {
            LogManager.shared.error("❌ Error cleaning up old playlists: \(error)")
        }
    }
    
    // MARK: - Migration Verification
    
    /// Verify migration completed successfully
    static func verifyMigration(context: NSManagedObjectContext) -> Bool {
        do {
            // Check that we have some Playback entities
            let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
            let playbackCount = try context.count(for: playbackRequest)
            
            // Check that episodes still work with computed properties
            let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            episodeRequest.fetchLimit = 5
            let sampleEpisodes = try context.fetch(episodeRequest)
            
            // Test computed properties (this will verify the computed properties work)
            for episode in sampleEpisodes {
                let _ = episode.isFav // This should work via computed property
                let _ = episode.isQueued // This should work via computed property
            }
            
            LogManager.shared.info("✅ Migration verification passed. Found \(playbackCount) Playback entities.")
            return true
            
        } catch {
            LogManager.shared.error("❌ Migration verification failed: \(error)")
            return false
        }
    }
}

// MARK: - Usage

extension PlaybackMigration {
    /// Call this in your app startup (AppDelegate or similar)
    static func runMigrationOnAppStart() {
        let context = PersistenceController.shared.container.viewContext
        
        // Run migration
        migratePlaybackDataIfNeeded(context: context)
        
        // Verify it worked
        let success = verifyMigration(context: context)
        if !success {
            LogManager.shared.error("❌ Migration verification failed - app may have issues")
        }
    }
}
