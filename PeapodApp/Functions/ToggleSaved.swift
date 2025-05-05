//
//  ToggleSaved.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-05.
//

import SwiftUI

@MainActor func toggleSaved(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    let context = episode.managedObjectContext ?? PersistenceController.shared.container.viewContext
    
    episode.isSaved.toggle()
    
    if episode.isSaved {
        episode.savedDate = Date()
    } else {
        episode.savedDate = nil
    }
    
    do {
        try context.save()
        episodesViewModel?.fetchSaved()
        print(episode.savedDate)
    } catch {
        print("Failed to remove episode from saved: \(error)")
    }
}
