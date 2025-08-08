//
//  Maintenance.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-08-07.
//

import Foundation
import CoreData

struct EpisodeMaintenance {
    
    /// Preference key to track if maintenance has been performed
    private static let maintenanceCompletedKey = "PeapodPurgev1"
    
    /// Performs one-time episode cleanup if not already completed
    /// - Parameter context: The Core Data managed object context
    static func performMaintenanceIfNeeded(context: NSManagedObjectContext) {
        // Check if maintenance has already been performed
        let hasCompleted = UserDefaults.standard.bool(forKey: maintenanceCompletedKey)
        
        if hasCompleted {
            LogManager.shared.info("Episode maintenance already completed, skipping")
            return
        }
        
        LogManager.shared.info("Starting episode maintenance - purging old unused episodes")
        
        Task {
            do {
                let deletedCount = try await purgeOldUnusedEpisodes(context: context)
                
                // Mark maintenance as completed
                UserDefaults.standard.set(true, forKey: maintenanceCompletedKey)
                
                LogManager.shared.info("Episode maintenance completed successfully. Deleted \(deletedCount) episodes")
                
            } catch {
                LogManager.shared.error("Episode maintenance failed: \(error)")
            }
        }
    }
    
    /// Purges episodes that meet the criteria for deletion
    /// - Parameter context: The Core Data managed object context
    /// - Returns: Number of deleted episodes
    @MainActor
    private static func purgeOldUnusedEpisodes(context: NSManagedObjectContext) async throws -> Int {
        
        // Create fetch request for episodes to delete
        let fetchRequest = createDeletionFetchRequest()
        
        // Fetch episodes in batches for memory efficiency
        let batchSize = 100
        fetchRequest.fetchBatchSize = batchSize
        
        var totalDeleted = 0
        var hasMoreEpisodes = true
        
        while hasMoreEpisodes {
            // Set fetch limit for this batch
            fetchRequest.fetchLimit = batchSize
            
            let episodesToDelete = try context.fetch(fetchRequest)
            
            if episodesToDelete.isEmpty {
                hasMoreEpisodes = false
                break
            }
            
            // Delete episodes in this batch
            for episode in episodesToDelete {
                context.delete(episode)
            }
            
            // Save the context for this batch
            try context.save()
            
            totalDeleted += episodesToDelete.count
            
            LogManager.shared.info("Deleted batch of \(episodesToDelete.count) episodes. Total deleted: \(totalDeleted)")
            
            // If we got fewer than the batch size, we're done
            if episodesToDelete.count < batchSize {
                hasMoreEpisodes = false
            }
        }
        
        return totalDeleted
    }
    
    /// Creates the fetch request for episodes that should be deleted
    /// - Returns: NSFetchRequest configured for deletion criteria
    private static func createDeletionFetchRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        
        // Calculate date 1 year ago
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        
        // Build compound predicate for deletion criteria
        let predicates = [
            // Older than 1 year (using airDate as the age reference)
            NSPredicate(format: "airDate < %@", oneYearAgo as NSDate),
            
            // Not played
            NSPredicate(format: "isPlayed == NO"),
            
            // Not in queue (assuming isQueued property exists, or check playlist relationship)
            createNotQueuedPredicate(),
            
            // Not favorited
            NSPredicate(format: "isFav == NO"),
            
            // Not saved
            NSPredicate(format: "isSaved == NO"),
            
            // No playback progress
            NSPredicate(format: "playbackPosition == 0")
        ]
        
        // Combine all predicates with AND
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        // Sort by airDate (oldest first) for consistent deletion order
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: true)]
        
        return request
    }
    
    /// Creates predicate to check if episode is not in queue
    /// - Returns: NSPredicate for not queued episodes
    private static func createNotQueuedPredicate() -> NSPredicate {
        // Based on your queueFetchRequest, episodes in queue have playlist.name == "Queue"
        // So we want episodes that either have no playlist or playlist.name != "Queue"
        return NSPredicate(format: "playlist == nil OR playlist.name != %@", "Queue")
    }
    
    /// Manual trigger for maintenance (for testing or manual execution)
    /// - Parameter context: The Core Data managed object context
    /// - Parameter force: If true, runs maintenance even if already completed
    static func performMaintenance(context: NSManagedObjectContext, force: Bool = false) {
        if force {
            UserDefaults.standard.removeObject(forKey: maintenanceCompletedKey)
        }
        
        performMaintenanceIfNeeded(context: context)
    }
    
    /// Checks if maintenance has been completed
    /// - Returns: True if maintenance has been performed
    static func hasMaintenanceCompleted() -> Bool {
        return UserDefaults.standard.bool(forKey: maintenanceCompletedKey)
    }
    
    /// Resets the maintenance flag (for testing purposes)
    static func resetMaintenanceFlag() {
        UserDefaults.standard.removeObject(forKey: maintenanceCompletedKey)
    }
    
    /// Preview function to see how many episodes would be deleted without actually deleting
    /// - Parameter context: The Core Data managed object context
    /// - Returns: Number of episodes that would be deleted
    static func previewDeletionCount(context: NSManagedObjectContext) throws -> Int {
        let fetchRequest = createDeletionFetchRequest()
        fetchRequest.resultType = .countResultType
        return try context.count(for: fetchRequest)
    }
}

// MARK: - Usage Examples

/*
// In your app initialization (e.g., in App delegate or main app struct):
EpisodeMaintenance.performMaintenanceIfNeeded(context: persistentContainer.viewContext)

// For manual testing:
EpisodeMaintenance.performMaintenance(context: viewContext, force: true)

// To preview deletion count:
let count = try EpisodeMaintenance.previewDeletionCount(context: viewContext)
print("Would delete \(count) episodes")

// To check if maintenance was completed:
let completed = EpisodeMaintenance.hasMaintenanceCompleted()
print("Maintenance completed: \(completed)")
*/
