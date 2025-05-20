//
//  EpisodeStateManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-19.
//

import Foundation
import CoreData

/// A helper class that centralizes episode state operations
final class EpisodeStateManager {
    // MARK: - Singleton
    static let shared = EpisodeStateManager()
    
    // MARK: - Properties
    private let backgroundContext: NSManagedObjectContext
    
    // MARK: - Initialization
    private init() {
        // Create a dedicated background context for all operations
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = PersistenceController.shared.container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = false
        self.backgroundContext = context
    }
    
    // MARK: - Public Methods
    
    /// Toggle the saved state of an episode
    func toggleSaved(_ episode: Episode) async {
        await performStateOperation(episode) { bgEpisode in
            bgEpisode.isSaved.toggle()
            
            if bgEpisode.isSaved {
                bgEpisode.savedDate = Date.now
                
                // Remove from queue if it's queued
                if bgEpisode.isQueued {
                    bgEpisode.isQueued = false
                    bgEpisode.queuePosition = -1
                    
                    // Remove from playlist relationship
                    let queuePlaylist = self.getQueuePlaylist()
                    queuePlaylist.removeFromItems(bgEpisode)
                    
                    // Update queue UI on main thread after transaction completes
                    Task { @MainActor in
                        QueueManager.shared.remove(episode)
                    }
                }
            } else {
                bgEpisode.savedDate = nil
            }
        }
    }
    
    /// Toggle the favorite state of an episode
    func toggleFav(_ episode: Episode) async {
        await performStateOperation(episode) { bgEpisode in
            bgEpisode.isFav.toggle()
            
            if bgEpisode.isFav {
                bgEpisode.favDate = Date.now
            } else {
                bgEpisode.favDate = nil
            }
        }
    }
    
    /// Mark an episode as played
    func markAsPlayed(_ episode: Episode) async {
        await performStateOperation(episode) { bgEpisode in
            bgEpisode.isPlayed = true
            bgEpisode.playedDate = Date.now
            bgEpisode.playbackPosition = bgEpisode.duration
        }
    }
    
    /// Mark an episode as unplayed
    func markAsUnplayed(_ episode: Episode) async {
        await performStateOperation(episode) { bgEpisode in
            bgEpisode.isPlayed = false
            bgEpisode.playedDate = nil
            bgEpisode.playbackPosition = 0
        }
    }
    
    /// Update playback position for an episode
    func updatePlaybackPosition(_ episode: Episode, position: Double) async {
        await performStateOperation(episode) { bgEpisode in
            bgEpisode.playbackPosition = position
            
            // Mark as played if position is close to the end
            let duration = bgEpisode.duration
            if duration > 0 {
                let progress = position / duration
                if progress > 0.95 { // 95% or more
                    bgEpisode.isPlayed = true
                    bgEpisode.playedDate = Date.now
                }
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Get or create the Queue playlist
    private func getQueuePlaylist() -> Playlist {
        let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", "Queue")
        
        if let existingPlaylist = try? backgroundContext.fetch(request).first {
            return existingPlaylist
        } else {
            let newPlaylist = Playlist(context: backgroundContext)
            newPlaylist.name = "Queue"
            return newPlaylist
        }
    }
    
    /// Generic method to perform a state operation on an episode
    private func performStateOperation(_ episode: Episode, operation: @escaping (Episode) -> Void) async {
        await withCheckedContinuation { continuation in
            backgroundContext.perform {
                do {
                    guard let bgEpisode = try self.backgroundContext.existingObject(with: episode.objectID) as? Episode else {
                        continuation.resume()
                        return
                    }
                    
                    // Perform the operation
                    operation(bgEpisode)
                    
                    // Save changes
                    try self.backgroundContext.save()
                    
                    // Merge to main context
                    DispatchQueue.main.async {
                        do {
                            // Refresh the episode object in the main context
                            PersistenceController.shared.container.viewContext.refresh(episode, mergeChanges: true)
                            try PersistenceController.shared.container.viewContext.save()
                            continuation.resume()
                        } catch {
                            print("❌ Error merging to main context: \(error)")
                            continuation.resume()
                        }
                    }
                } catch {
                    print("❌ Error performing episode state operation: \(error)")
                    self.backgroundContext.rollback()
                    continuation.resume()
                }
            }
        }
    }
}
