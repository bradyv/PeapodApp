//
//  Utilities.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-21.
//

import Foundation
import CoreData

func removeDuplicateEpisodes(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Episode> = Episode.fetchRequest()
    
    do {
        let episodes = try context.fetch(request)
        
        // Group by audio URL
        let grouped = Dictionary(grouping: episodes, by: { $0.audio ?? "nil" })

        for (_, duplicates) in grouped {
            guard duplicates.count > 1 else { continue }

            // Choose which one to keep: the one with the most complete data
            let episodeToKeep = duplicates.max { a, b in
                let scoreA = (a.title?.count ?? 0) + (a.episodeDescription?.count ?? 0)
                let scoreB = (b.title?.count ?? 0) + (b.episodeDescription?.count ?? 0)
                return scoreA < scoreB
            }

            for episode in duplicates {
                if episode != episodeToKeep {
                    context.delete(episode)
                }
            }
        }

        try context.save()
        print("✅ Duplicates removed successfully.")
    } catch {
        print("❌ Error removing duplicates: \(error)")
    }
}

func ensureQueuePlaylistExists(context: NSManagedObjectContext) {
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", "Queue")

    let existing = (try? context.fetch(request))?.first
    if existing == nil {
        let playlist = Playlist(context: context)
        playlist.name = "Queue"
        try? context.save()
        print("✅ Created 'Queue' playlist")
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
        print("✅ Migrated \(oldQueuedEpisodes.count) episodes to the playlist queue.")
    } catch {
        print("❌ Failed to migrate queue episodes: \(error.localizedDescription)")
    }
}
