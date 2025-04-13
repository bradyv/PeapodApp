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

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("❌ Failed to find persistent store description.")
        }

        // Set the CloudKit container ID
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.bradyv.Peapod")

        // Optional: support in-memory store for previews/tests
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        // Enable remote change notifications
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("❌ Unresolved error loading store: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
