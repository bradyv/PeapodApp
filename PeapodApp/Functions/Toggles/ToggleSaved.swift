//
//  ToggleSaved.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-05.
//

import SwiftUI

@MainActor func toggleSaved(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    let context = episode.managedObjectContext ?? PersistenceController.shared.container.viewContext
    if episode.isQueued && episode.isSaved == false {
        removeFromQueue(episode)
    }
    
    episode.isSaved.toggle()
    
    if episode.isSaved {
        episode.savedDate = Date()
    } else {
        episode.savedDate = nil
    }
    
    do {
        try context.save()
//        episodesViewModel?.fetchSaved()
    } catch {
        print("Failed to remove episode from saved: \(error)")
    }
}
