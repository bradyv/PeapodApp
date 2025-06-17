//
//  Persistence.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer
    
    // 🚀 NEW: CloudKit sync coordination
    private var cloudKitSyncInProgress = false
    private let cloudKitSyncLock = NSLock()
    private var lastCloudKitProcessTime = Date.distantPast
    
    // 🚀 NEW: Dedicated contexts for different operations
    private lazy var _episodeRefreshContext: NSManagedObjectContext = {
        let context = container.newBackgroundContext()
        context.name = "EpisodeRefreshContext"
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.stalenessInterval = 0.0 // Always get fresh data
        
        // 🚀 Enhanced: Better handling of concurrent modifications
        context.shouldDeleteInaccessibleFaults = false
        
        return context
    }()
    
    private lazy var _queueManagementContext: NSManagedObjectContext = {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.name = "QueueManagementContext"
        context.parent = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return context
    }()

    private init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "PeapodApp")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("❌ Failed to get a store description.")
        }

        // 🚀 DEBUG: Print current store description
        print("🔍 Store URL: \(description.url?.absoluteString ?? "none")")
        print("🔍 Store type: \(description.type)")
        
        // 🚀 SAFETY: Try to detect and handle corrupted stores
        if let storeURL = description.url,
           FileManager.default.fileExists(atPath: storeURL.path) {
            
            // Check if the store file is corrupted by trying to get its metadata
            do {
                let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                    ofType: NSSQLiteStoreType,
                    at: storeURL,
                    options: nil
                )
                print("✅ Store metadata valid: \(metadata.keys.count) keys")
            } catch {
                print("⚠️ Store metadata check failed: \(error)")
                print("🔧 Attempting to backup and recreate store...")
                
                // Backup the corrupted store
                let backupURL = storeURL.appendingPathExtension("backup.\(Date().timeIntervalSince1970)")
                try? FileManager.default.moveItem(at: storeURL, to: backupURL)
                
                // Remove associated files
                let walURL = storeURL.appendingPathExtension("sqlite-wal")
                let shmURL = storeURL.appendingPathExtension("sqlite-shm")
                try? FileManager.default.removeItem(at: walURL)
                try? FileManager.default.removeItem(at: shmURL)
                
                print("🔧 Store backed up to: \(backupURL.lastPathComponent)")
            }
        }

        // Enable CloudKit syncing
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.bradyv.PeapodApp")
        
        // 🚀 ENHANCED: Store options for better concurrency and debugging
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // 🚀 SAFETY: Migration options
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        
        // 🚀 NEW: WAL mode for better concurrent access
        var pragmas: [String: Any] = [:]
        pragmas["journal_mode"] = "WAL"
        pragmas["synchronous"] = "NORMAL"
        pragmas["cache_size"] = 10000
        pragmas["temp_store"] = "MEMORY"
        description.setOption(pragmas as NSDictionary, forKey: NSSQLitePragmasOption)

        // 🚀 ENHANCED: Better error handling and debugging
        container.loadPersistentStores { [self] storeDescription, error in
            if let error = error as NSError? {
                print("❌ Core Data Error Details:")
                print("   Error Code: \(error.code)")
                print("   Error Domain: \(error.domain)")
                print("   Error Description: \(error.localizedDescription)")
                print("   Error User Info: \(error.userInfo)")
                
                // 🚀 SAFETY: Handle specific error types
                if error.domain == NSCocoaErrorDomain {
                    switch error.code {
                    case NSPersistentStoreIncompatibleVersionHashError:
                        print("🔧 Version hash error - migration needed")
                        // Could implement automatic migration or reset here
                    case NSCoreDataError:
                        print("🔧 Core Data error - possible corruption")
                    case NSMigrationMissingSourceModelError:
                        print("🔧 Migration model missing")
                    default:
                        print("🔧 Other Core Data error")
                    }
                }
                
                // 🚀 DEBUG: Try to get more specific error information
                if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                    print("   Underlying Error: \(underlyingError.localizedDescription)")
                }
                
                if let detailedErrors = error.userInfo[NSDetailedErrorsKey] as? [NSError] {
                    for (index, detailedError) in detailedErrors.enumerated() {
                        print("   Detailed Error \(index): \(detailedError.localizedDescription)")
                    }
                }
                
                // 🚀 LAST RESORT: Reset the store if it's corrupted
                print("🔧 Attempting emergency store reset...")
                self.performEmergencyReset()
                
                // Try loading again after reset
                container.loadPersistentStores { secondStoreDescription, secondError in
                    if let secondError = secondError {
                        fatalError("❌ Failed to load store even after reset: \(secondError)")
                    } else {
                        LogManager.shared.info("✅ Store loaded successfully after reset: \(secondStoreDescription)")
                    }
                }
                
            } else {
                LogManager.shared.info("✅ Successfully loaded store: \(storeDescription)")
            }
        }

        // Configure main context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "MainViewContext"
        
        // 🚀 DEBUG: Add context debugging
        container.viewContext.shouldDeleteInaccessibleFaults = false
        
        // 🚀 NEW: Set up change tracking for better debugging
        setupChangeTracking()
        
        // 🚀 ENHANCED: CloudKit remote change handling with debouncing
        setupRemoteChangeHandling()
    }
    
    // 🚀 NEW: Emergency reset function
    private func performEmergencyReset() {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            print("❌ No store URL found for reset")
            return
        }
        
        print("🔧 Performing emergency Core Data reset...")
        
        do {
            // Remove all store files
            let fileManager = FileManager.default
            
            // Main store file
            if fileManager.fileExists(atPath: storeURL.path) {
                try fileManager.removeItem(at: storeURL)
                print("✅ Removed main store file")
            }
            
            // WAL file
            let walURL = storeURL.appendingPathExtension("sqlite-wal")
            if fileManager.fileExists(atPath: walURL.path) {
                try fileManager.removeItem(at: walURL)
                print("✅ Removed WAL file")
            }
            
            // SHM file
            let shmURL = storeURL.appendingPathExtension("sqlite-shm")
            if fileManager.fileExists(atPath: shmURL.path) {
                try fileManager.removeItem(at: shmURL)
                print("✅ Removed SHM file")
            }
            
            print("✅ Emergency reset completed")
            
        } catch {
            print("❌ Failed to perform emergency reset: \(error)")
        }
    }
    
    // 🚀 NEW: Get appropriate context for episode refresh operations
    func episodeRefreshContext() -> NSManagedObjectContext {
        return _episodeRefreshContext
    }
    
    // 🚀 NEW: Get appropriate context for queue management
    func queueContext() -> NSManagedObjectContext {
        return _queueManagementContext
    }
    
    // 🚀 NEW: Create a temporary context for one-off operations
    func newTemporaryContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.stalenessInterval = 0.0
        return context
    }
    
    // 🚀 ENHANCED: Change tracking with better error handling
    private func setupChangeTracking() {
        // Track when objects are updated to help debug duplicates
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: container.viewContext,
            queue: .main
        ) { notification in
            do {
                if let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
                    let episodes = insertedObjects.compactMap { $0 as? Episode }
                    if !episodes.isEmpty {
                        print("📝 Main context: \(episodes.count) episodes inserted")
                        for episode in episodes.prefix(3) { // Log first 3 for debugging
                            let title = episode.title ?? "Unknown"
                            let guid = episode.guid ?? "none"
                            print("   - \(title) (GUID: \(String(guid.prefix(20))))")
                        }
                    }
                }
                
                if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
                    let episodes = updatedObjects.compactMap { $0 as? Episode }
                    if episodes.count > 5 { // Only log if significant updates
                        print("📝 Main context: \(episodes.count) episodes updated")
                    }
                }
            } catch {
                print("❌ Error in change tracking: \(error)")
            }
        }
    }
    
    // 🚀 ENHANCED: CloudKit remote change handling with debouncing
    private func setupRemoteChangeHandling() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRemoteChangesWithDebouncing(notification)
        }
    }
    
    // 🚀 NEW: Debounced remote change handling to reduce noise
    private func handleRemoteChangesWithDebouncing(_ notification: Notification) {
        cloudKitSyncLock.lock()
        defer { cloudKitSyncLock.unlock() }
        
        let now = Date()
        let timeSinceLastProcess = now.timeIntervalSince(lastCloudKitProcessTime)
        
        // 🚀 DEBOUNCE: Only process if it's been more than 2 seconds since last process
        if timeSinceLastProcess < 2.0 {
            // print("⏩ Skipping CloudKit sync - too frequent (\(String(format: "%.1f", timeSinceLastProcess))s ago)")
            return
        }
        
        // 🚀 SKIP: Don't process if already in progress
        if cloudKitSyncInProgress {
            // print("⏩ Skipping CloudKit sync - already in progress")
            return
        }
        
        cloudKitSyncInProgress = true
        lastCloudKitProcessTime = now
        
        print("☁️ Processing CloudKit remote changes (debounced)")
        UserDefaults.standard.set(Date(), forKey: "lastCloudSyncDate")
        
        // 🚀 ASYNC: Process changes asynchronously to avoid blocking
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.handleRemoteChanges(notification)
            
            // Reset sync flag after a delay to allow batching
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.cloudKitSyncLock.lock()
                self?.cloudKitSyncInProgress = false
                self?.cloudKitSyncLock.unlock()
            }
        }
    }
    
    // 🚀 ENHANCED: Better remote change processing
    private func handleRemoteChanges(_ notification: Notification) {
        do {
            // Refresh all contexts to get latest changes
            container.viewContext.perform {
                self.container.viewContext.refreshAllObjects()
            }
            
            _episodeRefreshContext.perform {
                self._episodeRefreshContext.refreshAllObjects()
            }
            
            // Post notification for UI updates (debounced)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
            }
        } catch {
            print("❌ Error handling remote changes: \(error)")
        }
    }
    
    // 🚀 NEW: Check if episode refresh should be paused for CloudKit sync
    func shouldPauseEpisodeRefresh() -> Bool {
        cloudKitSyncLock.lock()
        defer { cloudKitSyncLock.unlock() }
        return cloudKitSyncInProgress
    }
    
    // 🚀 NEW: Safe save operation with retry logic
    func safeSave(context: NSManagedObjectContext, description: String = "Unknown operation") {
        guard context.hasChanges else {
            // print("ℹ️ No changes to save for: \(description)")
            return
        }
        
        context.perform {
            var retryCount = 0
            let maxRetries = 3
            
            while retryCount < maxRetries {
                do {
                    try context.save()
                    print("✅ Successfully saved: \(description)")
                    
                    // If this is a child context, save parent too
                    if let parent = context.parent, parent.hasChanges {
                        try parent.save()
                        print("✅ Parent context saved for: \(description)")
                    }
                    
                    return
                } catch let error as NSError {
                    retryCount += 1
                    print("❌ Save attempt \(retryCount) failed for \(description): \(error.localizedDescription)")
                    
                    if retryCount < maxRetries {
                        // Wait a bit before retrying
                        Thread.sleep(forTimeInterval: 0.1 * Double(retryCount))
                        
                        // Refresh context and try again
                        context.refreshAllObjects()
                    } else {
                        // Final attempt failed, rollback
                        print("❌ Final save attempt failed for \(description), rolling back")
                        context.rollback()
                        
                        // Log detailed error information
                        if let detailedErrors = error.userInfo[NSDetailedErrorsKey] as? [NSError] {
                            for detailedError in detailedErrors {
                                print("   Detailed error: \(detailedError.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // 🚀 NEW: Deduplication helper
    func performDeduplication() {
        let context = newTemporaryContext()
        context.perform {
            // This would call your existing mergeDuplicateEpisodes function
            // but in a dedicated context
            print("🔍 Running deduplication check...")
            
            do {
                // Example: Find episodes with same GUID
                let request: NSFetchRequest<Episode> = Episode.fetchRequest()
                request.predicate = NSPredicate(format: "guid != nil AND guid != ''")
                
                let episodes = try context.fetch(request)
                let groupedByGuid = Dictionary(grouping: episodes) { $0.guid ?? "" }
                
                var duplicatesFound = 0
                for (guid, episodeGroup) in groupedByGuid where episodeGroup.count > 1 {
                    duplicatesFound += episodeGroup.count - 1
                    print("🔍 Found \(episodeGroup.count) episodes with GUID: \(String(guid.prefix(20)))...")
                    
                    // Keep the first one, remove others
                    let episodesToRemove = Array(episodeGroup.dropFirst())
                    for episode in episodesToRemove {
                        context.delete(episode)
                    }
                }
                
                if duplicatesFound > 0 {
                    try context.save()
                    print("✅ Removed \(duplicatesFound) duplicate episodes")
                } else {
                    print("✅ No duplicates found")
                }
                
            } catch {
                print("❌ Deduplication failed: \(error)")
                context.rollback()
            }
        }
    }
}

// 🚀 NEW: Notification for CloudKit changes
extension Notification.Name {
    static let cloudKitDataDidChange = Notification.Name("cloudKitDataDidChange")
}

// 🚀 NEW: Extension for common episode operations
extension PersistenceController {
    
    /// Find episode by ID across all contexts safely
    func findEpisode(id: String, in context: NSManagedObjectContext? = nil) -> Episode? {
        let workingContext = context ?? container.viewContext
        
        do {
            let request: NSFetchRequest<Episode> = Episode.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            
            return try workingContext.fetch(request).first
        } catch {
            print("❌ Error finding episode by ID: \(error)")
            return nil
        }
    }
    
    /// Find episodes by GUID safely
    func findEpisodes(guid: String, in context: NSManagedObjectContext? = nil) -> [Episode] {
        let workingContext = context ?? container.viewContext
        
        do {
            let request: NSFetchRequest<Episode> = Episode.fetchRequest()
            request.predicate = NSPredicate(format: "guid == %@", guid)
            
            return try workingContext.fetch(request)
        } catch {
            print("❌ Error finding episodes by GUID: \(error)")
            return []
        }
    }
    
    /// Check if episode exists by multiple criteria
    func episodeExists(guid: String?, audioUrl: String?, title: String?, podcast: Podcast, in context: NSManagedObjectContext? = nil) -> Episode? {
        let workingContext = context ?? container.viewContext
        
        do {
            // Try GUID first
            if let guid = guid, !guid.isEmpty {
                let guidRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                guidRequest.predicate = NSPredicate(format: "guid == %@ AND podcast == %@", guid, podcast)
                guidRequest.fetchLimit = 1
                
                if let episode = try workingContext.fetch(guidRequest).first {
                    return episode
                }
            }
            
            // Try audio URL
            if let audioUrl = audioUrl, !audioUrl.isEmpty {
                let audioRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                audioRequest.predicate = NSPredicate(format: "audio == %@ AND podcast == %@", audioUrl, podcast)
                audioRequest.fetchLimit = 1
                
                if let episode = try workingContext.fetch(audioRequest).first {
                    return episode
                }
            }
            
            return nil
        } catch {
            print("❌ Error checking episode existence: \(error)")
            return nil
        }
    }
}
