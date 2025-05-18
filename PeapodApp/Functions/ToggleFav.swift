//
//  ToggleFav.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI
import CoreData

@MainActor
func toggleFav(_ episode: Episode) {
    let objectID = episode.objectID
    
    // Do Core Data operations in background
    Task.detached(priority: .background) {
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = PersistenceController.shared.container.viewContext
        
        await backgroundContext.perform {
            do {
                guard let backgroundEpisode = try backgroundContext.existingObject(with: objectID) as? Episode else { return }
                
                // Toggle favorite state
                backgroundEpisode.isFav.toggle()
                
                try backgroundContext.save()
                print("✅ Episode favorite state toggled: \(backgroundEpisode.title ?? "Episode")")
            } catch {
                print("❌ Failed to toggle favorite episode: \(error)")
                backgroundContext.rollback()
            }
        }
        
        // Save to persistent store
        await MainActor.run {
            try? PersistenceController.shared.container.viewContext.save()
        }
    }
}
