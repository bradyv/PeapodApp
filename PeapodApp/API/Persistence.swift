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

    private init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "PeapodApp")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("❌ Failed to get a store description.")
        }

        // Enable CloudKit syncing
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.bradyv.PeapodApp")

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("❌ Unresolved error loading store: \(error), \(error.userInfo)")
            } else {
                print("✅ Successfully loaded store: \(storeDescription)")
            }
        }

        // Merge changes from other devices
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
