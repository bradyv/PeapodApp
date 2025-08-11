//
//  Utilities.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-21.
//

import Foundation
import CoreData

func runDeduplicationOnceIfNeeded(context: NSManagedObjectContext) {
    let versionKey = "com.bradyv.Peapod.Dev.didDeduplicatePodcasts.v1"
    // Uncomment this line if you want to skip if already run
    // if UserDefaults.standard.bool(forKey: versionKey) {
    //     return
    // }

    deduplicatePodcasts(context: context)
    UserDefaults.standard.set(true, forKey: versionKey)
}

func oneTimeSplashMark(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
    request.predicate = NSPredicate(format: "isSubscribed == YES")
    
    let hasSubscriptions = (try? context.fetch(request))?.isEmpty == false
    
    UserDefaults.standard.set(!hasSubscriptions, forKey: "showOnboarding")
}

func migrateMissingEpisodeGUIDs(context: NSManagedObjectContext) {
    let migrateGUIDKey = "com.bradyv.Peapod.Dev.migrateMissingGUIDs.v1"
    if UserDefaults.standard.bool(forKey: migrateGUIDKey) {
        return
    }
    
    context.perform {
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "guid == nil")

        do {
            let episodes = try context.fetch(request)
            print("🔄 Found \(episodes.count) episode(s) missing GUIDs")

            for episode in episodes {
                if let title = episode.title, let airDate = episode.airDate {
                    let key = "\(title.lowercased())_\(airDate.timeIntervalSince1970)"
                    episode.guid = key
                } else if let title = episode.title {
                    // Fall back to title alone if no airDate
                    episode.guid = title.lowercased()
                } else {
                    // Last resort, random UUID
                    episode.guid = UUID().uuidString
                }
            }

            try context.save()
            LogManager.shared.info("✅ Migration completed: GUIDs populated")
            UserDefaults.standard.set(true, forKey: migrateGUIDKey)
        } catch {
            LogManager.shared.error("❌ Migration failed: \(error)")
        }
    }
}

func ensureQueuePlaylistExists(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", "Queue")

    let existing = (try? context.fetch(request))?.first
    if existing == nil {
        let playlist = Playlist(context: context)
        playlist.name = "Queue"
        playlist.id = UUID()
        playlist.episodeIdArray = []
        try? context.save()
        LogManager.shared.info("✅ Created 'Queue' playlist")
    }
}

func ensurePlayedPlaylistExists(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", "Played")
    
    let existing = (try? context.fetch(request))?.first
    if existing == nil {
        let playlist = Playlist(context: context)
        playlist.name = "Played"
        playlist.id = UUID()
        playlist.episodeIdArray = []
        try? context.save()
        LogManager.shared.info("✅ Created 'Played' playlist")
    }
}

func ensureFavoritesPlaylistExists(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", "Favorites")
    
    let existing = (try? context.fetch(request))?.first
    if existing == nil {
        let playlist = Playlist(context: context)
        playlist.name = "Favorites"
        playlist.id = UUID()
        playlist.episodeIdArray = []
        try? context.save()
        LogManager.shared.info("✅ Created 'Favorites' playlist")
    }
}

func migrateOldQueueToPlaylist(context: NSManagedObjectContext) {
    let queueMigrateKey = "com.bradyv.Peapod.Dev.queueMigrateKey.v1"
    if UserDefaults.standard.bool(forKey: queueMigrateKey) {
        return
    }
    
    // This function is now deprecated since we're using episodeIds instead of relationships
    // But we'll mark it as complete to avoid repeated execution
    UserDefaults.standard.set(true, forKey: queueMigrateKey)
    LogManager.shared.info("✅ Skipped old queue migration (using new playlist system)")
}

func migrateOldBooleanPropertiesToPlaylists(context: NSManagedObjectContext) {
    let migrationKey = "com.bradyv.Peapod.Dev.booleanToPlaylistMigration.v1"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    LogManager.shared.info("🔄 Starting migration from boolean properties to playlists...")
    
    // Ensure playlists exist
    let queuePlaylist = getPlaylist(named: "Queue", context: context)
    let playedPlaylist = getPlaylist(named: "Played", context: context)
    let favoritesPlaylist = getPlaylist(named: "Favorites", context: context)
    
    // Fetch all episodes that have old boolean properties set
    let request: NSFetchRequest<Episode> = Episode.fetchRequest()
    // Note: You'll need to remove these predicates once you remove the boolean attributes
    // request.predicate = NSPredicate(format: "isQueued == YES OR isPlayed == YES OR isFav == YES")
    
    do {
        let episodes = try context.fetch(request)
        var queueIds: [String] = []
        var playedIds: [String] = []
        var favIds: [String] = []
        
        for episode in episodes {
            guard let episodeId = episode.id else { continue }
            
            // Check old boolean properties and add to appropriate playlists
            // Note: Remove these checks once you remove the boolean attributes
            /*
            if episode.isQueued {
                queueIds.append(episodeId)
                
                // Create playback state for queue position
                let playback = episode.getOrCreatePlaybackState()
                playback.queuePosition = episode.queuePosition
            }
            
            if episode.isPlayed {
                playedIds.append(episodeId)
                
                // Migrate playback data
                let playback = episode.getOrCreatePlaybackState()
                playback.playedDate = episode.playedDate
                playback.playCount = episode.playCount
                playback.playbackPosition = episode.playbackPosition
            }
            
            if episode.isFav {
                favIds.append(episodeId)
                
                // Migrate favorite date
                let playback = episode.getOrCreatePlaybackState()
                playback.favDate = episode.favDate
            }
            */
        }
        
        // Update playlists with episode IDs
        queuePlaylist.episodeIdArray = queueIds
        playedPlaylist.episodeIdArray = playedIds
        favoritesPlaylist.episodeIdArray = favIds
        
        try context.save()
        
        LogManager.shared.info("✅ Migrated \(queueIds.count) queued, \(playedIds.count) played, \(favIds.count) favorite episodes")
        UserDefaults.standard.set(true, forKey: migrationKey)
        
    } catch {
        LogManager.shared.error("❌ Failed to migrate boolean properties: \(error)")
    }
}

func migrateOldPlaylistRelationshipsToEpisodeIds(context: NSManagedObjectContext) {
    let migrationKey = "com.bradyv.Peapod.Dev.playlistRelationshipMigration.v1"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    LogManager.shared.info("🔄 Starting migration from playlist relationships to episode IDs...")
    
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    
    do {
        let playlists = try context.fetch(request)
        
        for playlist in playlists {
            // Note: This assumes you still have the old relationship for migration
            // Remove this code once migration is complete
            /*
            if let episodes = playlist.episodes as? Set<Episode> {
                let episodeIds = episodes.compactMap { $0.id }
                playlist.episodeIdArray = episodeIds
                
                LogManager.shared.info("Migrated playlist '\(playlist.name ?? "Unknown")' with \(episodeIds.count) episodes")
            }
            */
        }
        
        try context.save()
        LogManager.shared.info("✅ Completed playlist relationship migration")
        UserDefaults.standard.set(true, forKey: migrationKey)
        
    } catch {
        LogManager.shared.error("❌ Failed to migrate playlist relationships: \(error)")
    }
}

// Updated deduplication function for the new model
func mergeDuplicateEpisodes(context: NSManagedObjectContext) {
    context.perform {
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()

        do {
            let episodes = try context.fetch(request)
            print("🔎 Checking \(episodes.count) episodes for duplicates")

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
                        // Transfer important flags using the new system
                        if duplicate.isQueued {
                            addEpisodeToPlaylist(keeper, playlistName: "Queue")
                            keeper.queuePosition = duplicate.queuePosition
                        }
                        
                        if duplicate.isPlayed {
                            addEpisodeToPlaylist(keeper, playlistName: "Played")
                            keeper.playedDate = max(keeper.playedDate ?? Date.distantPast, duplicate.playedDate ?? Date.distantPast)
                        }
                        
                        if duplicate.isFav {
                            addEpisodeToPlaylist(keeper, playlistName: "Favorites")
                            keeper.favDate = max(keeper.favDate ?? Date.distantPast, duplicate.favDate ?? Date.distantPast)
                        }

                        // Transfer playback position
                        if duplicate.playbackPosition > 0 {
                            keeper.playbackPosition = max(keeper.playbackPosition, duplicate.playbackPosition)
                        }

                        context.delete(duplicate)
                        duplicatesFound += 1
                    }
                }
            }

            try context.save()
            LogManager.shared.info("✅ Merged and deleted \(duplicatesFound) duplicate episode(s)")
        } catch {
            LogManager.shared.error("❌ Failed merging duplicates: \(error)")
        }
    }
}

// Updated deduplication for podcasts with new episode relationship
func deduplicatePodcasts(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()

    do {
        let podcasts = try context.fetch(request)
        
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
                
                if let episodes = try? context.fetch(episodeRequest) {
                    for episode in episodes {
                        episode.podcastId = primary.id
                    }
                }

                context.delete(duplicate)
            }
        }

        try context.save()
        LogManager.shared.info("✅ Enhanced podcast deduplication complete.")
    } catch {
        LogManager.shared.error("❌ Failed to deduplicate podcasts: \(error)")
    }
}
