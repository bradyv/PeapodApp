//
//  Maintenance.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-08-07.
//

import Foundation
import CoreData
import SwiftUI

struct EpisodeMaintenance {
    
    /// Preference key to track if maintenance has been performed
    private static let maintenanceCompletedKey = "PeapodPurgev1"
    
    /// Completion handler for maintenance operations
    typealias MaintenanceCompletion = (Result<Int, Error>) -> Void
    
    /// Performs one-time episode cleanup if not already completed
    /// - Parameters:
    ///   - context: The Core Data managed object context
    ///   - forced: If true, runs even if already completed and shows confirmation alert
    ///   - completion: Optional completion handler with deletion count or error
    static func performMaintenanceIfNeeded(
        context: NSManagedObjectContext,
        forced: Bool = false,
        completion: MaintenanceCompletion? = nil
    ) {
        // Check if maintenance has already been performed
        if !forced {
            let hasCompleted = UserDefaults.standard.bool(forKey: maintenanceCompletedKey)
            
            if hasCompleted {
                LogManager.shared.info("Episode maintenance already completed, skipping")
                completion?(.success(0))
                return
            }
        }
        
        // If forced, show confirmation alert first
        if forced {
            Task {
                do {
                    let countToDelete = try previewDeletionCount(context: context)
                    
                    await MainActor.run {
                        showConfirmationAlert(
                            countToDelete: countToDelete,
                            context: context,
                            completion: completion
                        )
                    }
                } catch {
                    LogManager.shared.error("Failed to preview deletion count: \(error)")
                    completion?(.failure(error))
                }
            }
            return
        }
        
        // Normal maintenance execution (not forced)
        executeMaintenance(context: context, completion: completion)
    }
    
    /// Shows confirmation alert before performing maintenance
    /// - Parameters:
    ///   - countToDelete: Number of episodes that would be deleted
    ///   - context: The Core Data managed object context
    ///   - completion: Completion handler for the operation
    @MainActor
    private static func showConfirmationAlert(
        countToDelete: Int,
        context: NSManagedObjectContext,
        completion: MaintenanceCompletion?
    ) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            LogManager.shared.warning("Could not find root view controller to show alert")
            completion?(.failure(MaintenanceError.cannotShowAlert))
            return
        }
        
        let title = "Confirm Maintenance"
        let message = countToDelete > 0
            ? "This will remove \(countToDelete) old episodes from your library. This action cannot be undone."
            : "No episodes need to be removed."
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        // Cancel action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            LogManager.shared.info("User cancelled maintenance operation")
            completion?(.success(0))
        })
        
        // Only show confirm button if there are episodes to delete
        if countToDelete > 0 {
            alert.addAction(UIAlertAction(title: "Remove Episodes", style: .destructive) { _ in
                LogManager.shared.info("User confirmed maintenance operation")
                executeMaintenance(context: context, completion: completion)
            })
        }
        
        // Present on the topmost view controller
        var topController = rootViewController
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }
        
        topController.present(alert, animated: true)
    }
    
    /// Executes the actual maintenance operation
    /// - Parameters:
    ///   - context: The Core Data managed object context
    ///   - completion: Optional completion handler
    private static func executeMaintenance(
        context: NSManagedObjectContext,
        completion: MaintenanceCompletion?
    ) {
        LogManager.shared.info("Starting episode maintenance - purging old unused episodes")
        
        Task {
            do {
                let deletedCount = try await purgeOldUnusedEpisodes(context: context)
                
                LogManager.shared.info("Episode maintenance completed successfully. Deleted \(deletedCount) episodes")
                
                // Show completion alert for forced runs
                await MainActor.run {
                    showCompletionAlert(deletedCount: deletedCount)
                }
                
                completion?(.success(deletedCount))
                
            } catch {
                LogManager.shared.error("Episode maintenance failed: \(error)")
                completion?(.failure(error))
            }
        }
    }
    
    /// Shows completion alert after maintenance
    /// - Parameter deletedCount: Number of episodes that were deleted
    @MainActor
    private static func showCompletionAlert(deletedCount: Int) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            LogManager.shared.warning("Could not find root view controller to show alert")
            return
        }
        
        let title = "Maintenance Complete"
        let message = "Successfully removed \(deletedCount) episodes from your library."
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Present on the topmost view controller
        var topController = rootViewController
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }
        
        topController.present(alert, animated: true)
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
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        
        // Build compound predicate for deletion criteria
        let predicates = [
            // Older than 1 year (using airDate as the age reference)
            NSPredicate(format: "airDate < %@", sixMonthsAgo as NSDate),
            
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
    /// - Parameters:
    ///   - context: The Core Data managed object context
    ///   - force: If true, runs maintenance even if already completed (shows confirmation alert)
    static func performMaintenance(context: NSManagedObjectContext, force: Bool = false) {
        if force {
            UserDefaults.standard.removeObject(forKey: maintenanceCompletedKey)
        }
        
        performMaintenanceIfNeeded(context: context, forced: force)
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

// MARK: - Error Types

enum MaintenanceError: Error, LocalizedError {
    case cannotShowAlert
    
    var errorDescription: String? {
        switch self {
        case .cannotShowAlert:
            return "Could not find view controller to show alert"
        }
    }
}

// MARK: - Usage Examples

/*
// Normal app startup (no alert, runs automatically if needed):
EpisodeMaintenance.performMaintenanceIfNeeded(context: persistentContainer.viewContext)

// Manual forced maintenance (shows confirmation dialog first):
EpisodeMaintenance.performMaintenance(context: viewContext, force: true)

// With completion handler:
EpisodeMaintenance.performMaintenanceIfNeeded(context: viewContext, forced: true) { result in
    switch result {
    case .success(let count):
        print("Maintenance completed, deleted \(count) episodes")
    case .failure(let error):
        print("Maintenance failed: \(error)")
    }
}

// Preview deletion count without running:
let count = try EpisodeMaintenance.previewDeletionCount(context: viewContext)
print("Would delete \(count) episodes")

// Check if maintenance was completed:
let completed = EpisodeMaintenance.hasMaintenanceCompleted()
print("Maintenance completed: \(completed)")
*/
