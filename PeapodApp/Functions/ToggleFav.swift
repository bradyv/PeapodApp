//
//  ToggleFav.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-16.
//

import SwiftUI

@MainActor func toggleFav(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
    let context = episode.managedObjectContext ?? PersistenceController.shared.container.viewContext
    
    episode.isFav.toggle()
    
    if episode.isFav {
        episode.favDate = Date()
    } else {
        episode.favDate = nil
    }
    
    do {
        try context.save()
        episodesViewModel?.fetchFavs()
    } catch {
        print("Failed to remove episode from favorites: \(error)")
    }
}
