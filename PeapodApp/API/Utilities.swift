//
//  Utilities.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-21.
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
        LogManager.shared.info("✅ Podcast deduplication complete.")
    } catch {
        LogManager.shared.error("❌ Failed to deduplicate podcasts: \(error)")
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
                        // Transfer important flags if they exist
                        if duplicate.isQueued { keeper.isQueued = true }
                        if duplicate.isSaved { keeper.isSaved = true }
                        if duplicate.isPlayed { keeper.isPlayed = true }
                        if duplicate.nowPlaying { keeper.nowPlaying = true }

                        if duplicate.queuePosition != nil {
                            keeper.queuePosition = duplicate.queuePosition
                        }
                        if duplicate.playbackPosition > 0 {
                            keeper.playbackPosition = max(keeper.playbackPosition, duplicate.playbackPosition)
                        }
                        if let playedDate = duplicate.playedDate {
                            if let existingDate = keeper.playedDate {
                                keeper.playedDate = max(existingDate, playedDate)
                            } else {
                                keeper.playedDate = playedDate
                            }
                        }

                        // Transfer playlist relationships if needed
                        if keeper.playlist == nil, let duplicatePlaylist = duplicate.playlist {
                            keeper.playlist = duplicatePlaylist
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

func migrateMissingEpisodeGUIDs(context: NSManagedObjectContext) {
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
        } catch {
            LogManager.shared.error("❌ Migration failed: \(error)")
        }
    }
}

func oneTimeSplashMark(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
    request.predicate = NSPredicate(format: "isSubscribed == YES")
    
    let hasSubscriptions = (try? context.fetch(request))?.isEmpty == false
    
    UserDefaults.standard.set(!hasSubscriptions, forKey: "showOnboarding")
}

func ensureQueuePlaylistExists(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", "Queue")

    let existing = (try? context.fetch(request))?.first
    if existing == nil {
        let playlist = Playlist(context: context)
        playlist.name = "Queue"
        try? context.save()
        LogManager.shared.info("✅ Created 'Queue' playlist")
    }
}

func migrateOldQueueToPlaylist(context: NSManagedObjectContext) {
    // Fetch or create the "Queue" playlist
    let playlistRequest = Playlist.fetchRequest()
    playlistRequest.predicate = NSPredicate(format: "name == %@", "Queue")
    playlistRequest.fetchLimit = 1

    let playlist: Playlist
    if let existing = try? context.fetch(playlistRequest).first {
        playlist = existing
    } else {
        playlist = Playlist(context: context)
        playlist.name = "Queue"
    }

    // Fetch episodes that were previously queued using the old system
    let request = Episode.fetchRequest()
    request.predicate = NSPredicate(format: "isQueued == YES AND playlist == nil")
    
    do {
        let oldQueuedEpisodes = try context.fetch(request)
        for episode in oldQueuedEpisodes {
            episode.playlist = playlist
            episode.isQueued = true // optional: ensure legacy flag is aligned
        }
        try context.save()
        LogManager.shared.info("✅ Migrated \(oldQueuedEpisodes.count) episodes to the playlist queue.")
    } catch {
        LogManager.shared.error("❌ Failed to migrate queue episodes: \(error.localizedDescription)")
    }
}
