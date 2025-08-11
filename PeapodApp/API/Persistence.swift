//
//  Persistence.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "PeapodApp")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("❌ Failed to get a store description.")
        }

        // REQUIRED: Enable persistent history tracking for CloudKit
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        
        // Enable CloudKit syncing
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.bradyv.PeapodApp")

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("❌ Unresolved error loading store: \(error), \(error.userInfo)")
            } else {
                LogManager.shared.info("✅ Successfully loaded store: \(storeDescription)")
            }
        }

        // Merge changes from other devices
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Set up CloudKit sync notifications
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(Date(), forKey: "lastCloudSyncDate")
        }
        
        // Optional: Clean up old history periodically
        setupHistoryCleanup()
    }
    
    private func setupHistoryCleanup() {
        // Clean up persistent history older than 7 days to prevent database bloat
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let deleteHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: sevenDaysAgo)
        
        do {
            try container.persistentStoreCoordinator.execute(deleteHistoryRequest, with: container.viewContext)
        } catch {
            LogManager.shared.warning("⚠️ Failed to clean up persistent history: \(error)")
        }
    }
}
