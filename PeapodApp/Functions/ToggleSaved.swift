//
//  ToggleSaved.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-05.
//

import SwiftUI
import CoreData

// MARK: - Toggle Saved (Updated for background Core Data operations)

@MainActor
func toggleSaved(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    let objectID = episode.objectID
    
    // Update UI immediately
    episodesViewModel?.fetchSaved()
    
    // Do Core Data operations in background
    Task.detached(priority: .background) {
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = PersistenceController.shared.container.viewContext
        
        await backgroundContext.perform {
            do {
                guard let backgroundEpisode = try backgroundContext.existingObject(with: objectID) as? Episode else { return }
                
                // If episode is queued and not saved, remove from queue first
                if backgroundEpisode.isQueued && !backgroundEpisode.isSaved {
                    removeFromQueueInBackground(episode: backgroundEpisode, context: backgroundContext)
                }
                
                // Toggle saved state
                backgroundEpisode.isSaved.toggle()
                
                if backgroundEpisode.isSaved {
                    backgroundEpisode.savedDate = Date()
                } else {
                    backgroundEpisode.savedDate = nil
                }
                
                try backgroundContext.save()
                print("✅ Episode saved state toggled: \(backgroundEpisode.title ?? "Episode")")
            } catch {
                print("❌ Failed to toggle saved episode: \(error)")
                backgroundContext.rollback()
            }
        }
        
        // Save to persistent store
        await MainActor.run {
            try? PersistenceController.shared.container.viewContext.save()
            episodesViewModel?.fetchSaved()
        }
    }
}

// MARK: - Private Helper for Background Queue Removal

private func removeFromQueueInBackground(episode: Episode, context: NSManagedObjectContext) {
    let queuePlaylist = getQueuePlaylist(context: context)
    
    // Only proceed if episode is actually in the queue
    if let episodes = queuePlaylist.items as? Set<Episode>, episodes.contains(episode) {
        queuePlaylist.removeFromItems(episode)
        episode.isQueued = false
        episode.queuePosition = -1
        
        // Reindex remaining episodes
        let remainingEpisodes = (queuePlaylist.items as? Set<Episode> ?? [])
            .sorted { $0.queuePosition < $1.queuePosition }
        
        for (index, ep) in remainingEpisodes.enumerated() {
            ep.queuePosition = Int64(index)
        }
        
        print("Episode removed from queue during save toggle: \(episode.title ?? "Episode")")
    }
}
