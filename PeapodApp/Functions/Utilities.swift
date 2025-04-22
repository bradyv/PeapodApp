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
