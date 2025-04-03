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

    private init() {
        container = NSPersistentContainer(name: "PeapodApp")

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("❌ Unresolved error loading store: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
