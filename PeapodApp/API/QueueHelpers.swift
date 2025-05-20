//
//  QueueHelpers.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-18.
//

import SwiftUI
import CoreData

// MARK: - Queue Management Functions

/// Toggle an episode in the queue
func toggleQueued(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.toggle(episode)
}

/// Add episode to front of queue (used when starting playback)
func addToFrontOfQueue(_ episode: Episode, pushingPrevious current: Episode? = nil, episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.addToFront(episode, pushingBack: current)
}

/// Remove an episode from the queue
func removeFromQueue(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.remove(episode)
}

/// Move an episode to a specific position in the queue
func moveEpisodeInQueue(_ episode: Episode, to position: Int, episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.move(episode, to: position)
}

/// Reorder the entire queue
func reorderQueue(_ episodes: [Episode], episodesViewModel: EpisodesViewModel? = nil) {
    QueueManager.shared.reorder(episodes)
}

// MARK: - Episode State Management

/// Toggle the saved state of an episode
func toggleSaved(_ episode: Episode) {
    // Create background context outside of the Task for better performance
    let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    backgroundContext.parent = PersistenceController.shared.container.viewContext
    backgroundContext.automaticallyMergesChangesFromParent = false
    
    var wasRemoved = false
    
    Task(priority: .userInitiated) {
        await withCheckedContinuation { continuation in
            backgroundContext.perform {
                do {
                    guard let bgEpisode = try backgroundContext.existingObject(with: episode.objectID) as? Episode else {
                        continuation.resume()
                        return
                    }
                    
                    bgEpisode.isSaved.toggle()
                    
                    if bgEpisode.isSaved {
                        bgEpisode.savedDate = Date.now
                        
                        // Remove from queue if it's queued
                        if bgEpisode.isQueued {
                            bgEpisode.isQueued = false
                            bgEpisode.queuePosition = -1
                            wasRemoved = true
                            
                            // Remove from playlist relationship
                            let queuePlaylist = getQueuePlaylist(context: backgroundContext)
                            queuePlaylist.removeFromItems(bgEpisode)
                        }
                    } else {
                        bgEpisode.savedDate = nil
                    }
                    
                    try backgroundContext.save()
                    
                    // Merge to main context asynchronously
                    DispatchQueue.main.async {
                        do {
                            try PersistenceController.shared.container.viewContext.save()
                            continuation.resume()
                        } catch {
                            print("❌ Error merging to main context: \(error)")
                            continuation.resume()
                        }
                    }
                } catch {
                    print("❌ Error toggling saved state: \(error)")
                    backgroundContext.rollback()
                    continuation.resume()
                }
            }
        }
        
        // If episode was removed from queue, update QueueManager UI
        if wasRemoved {
            await MainActor.run {
                QueueManager.shared.remove(episode)
            }
        }
    }
}

/// Toggle the favorite state of an episode
func toggleFav(_ episode: Episode) {
    // Create background context outside of the Task for better performance
    let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    backgroundContext.parent = PersistenceController.shared.container.viewContext
    backgroundContext.automaticallyMergesChangesFromParent = false
    
    Task(priority: .userInitiated) {
        await withCheckedContinuation { continuation in
            backgroundContext.perform {
                do {
                    guard let bgEpisode = try backgroundContext.existingObject(with: episode.objectID) as? Episode else {
                        continuation.resume()
                        return
                    }
                    
                    bgEpisode.isFav.toggle()
                    
                    if bgEpisode.isFav {
                        bgEpisode.favDate = Date.now
                    } else {
                        bgEpisode.favDate = nil
                    }
                    
                    try backgroundContext.save()
                    
                    // Merge to main context asynchronously
                    DispatchQueue.main.async {
                        do {
                            try PersistenceController.shared.container.viewContext.save()
                            continuation.resume()
                        } catch {
                            print("❌ Error merging to main context: \(error)")
                            continuation.resume()
                        }
                    }
                } catch {
                    print("❌ Error toggling favorite state: \(error)")
                    backgroundContext.rollback()
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Playlist Helper

/// Get or create the Queue playlist in the given context
func getQueuePlaylist(context: NSManagedObjectContext) -> Playlist {
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", "Queue")
    
    if let existingPlaylist = try? context.fetch(request).first {
        return existingPlaylist
    } else {
        let newPlaylist = Playlist(context: context)
        newPlaylist.name = "Queue"
        try? context.save()
        return newPlaylist
    }
}
