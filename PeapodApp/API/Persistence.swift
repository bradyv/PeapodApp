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
        // Use NSPersistentCloudKitContainer for CloudKit support
        container = NSPersistentCloudKitContainer(name: "PeapodApp")

        if inMemory {
            container.persistentStoreDescriptions.forEach { $0.url = URL(fileURLWithPath: "/dev/null") }
        } else {
            setupPersistentStores()
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("❌ Unresolved error loading store: \(error), \(error.userInfo)")
            } else {
                LogManager.shared.info("✅ Successfully loaded store: \(storeDescription)")
                LogManager.shared.info("   Configuration: \(storeDescription.configuration ?? "Default")")
                LogManager.shared.info("   CloudKit: \(storeDescription.cloudKitContainerOptions != nil)")
            }
        }

        // Merge changes from other devices
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Set up CloudKit sync notifications
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(Date(), forKey: "lastCloudSyncDate")
            LogManager.shared.info("📱 CloudKit remote change detected")
        }
        
        // Optional: Clean up old history periodically
        setupHistoryCleanup()
    }
    
    private func setupPersistentStores() {
        // Clear any existing store descriptions
        container.persistentStoreDescriptions.removeAll()
        
        // CLOUDKIT SYNCED STORE (Sync configuration)
        let syncStoreURL = URL.storeURL(for: "SyncStore", databaseName: "PeapodApp_Sync")
        let syncStoreDescription = NSPersistentStoreDescription(url: syncStoreURL)
        syncStoreDescription.configuration = "Sync"
        
        // Enable CloudKit for synced store
        syncStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        syncStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        syncStoreDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.bradyv.PeapodApp")
        
        // LOCAL-ONLY STORE (Local configuration)
        let localStoreURL = URL.storeURL(for: "LocalStore", databaseName: "PeapodApp_Local")
        let localStoreDescription = NSPersistentStoreDescription(url: localStoreURL)
        localStoreDescription.configuration = "Local"
        
        // Local store settings (no CloudKit)
        localStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        localStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        // NO cloudKitContainerOptions = stays local only
        
        // Add both stores to the container
        container.persistentStoreDescriptions = [syncStoreDescription, localStoreDescription]
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

// MARK: - Helper Extension for Store URLs
extension URL {
    static func storeURL(for appGroup: String, databaseName: String) -> URL {
        guard let fileContainer = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Shared file container could not be created.")
        }
        
        return fileContainer.appendingPathComponent("\(databaseName).sqlite")
    }
}
