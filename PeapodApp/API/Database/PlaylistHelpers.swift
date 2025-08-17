//
//  PlaylistHelpers.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-08-11.
//

import Foundation
import CoreData

// MARK: - Backward Compatibility Helper Functions

/// Thread-safe playlist getter for use in background contexts
func getPlaylistThreadSafe(named playlistName: String, context: NSManagedObjectContext) -> MockPlaylist {
    switch playlistName {
    case "Queue":
        let episodes = getQueuedEpisodes(context: context)
        return MockPlaylist(episodeIdArray: episodes.compactMap { $0.id })
    case "Played":
        let episodes = getPlayedEpisodes(context: context)
        return MockPlaylist(episodeIdArray: episodes.compactMap { $0.id })
    case "Favorites":
        let episodes = getFavoriteEpisodes(context: context)
        return MockPlaylist(episodeIdArray: episodes.compactMap { $0.id })
    default:
        LogManager.shared.error("❌ Unknown playlist name: \(playlistName)")
        return MockPlaylist(episodeIdArray: [])
    }
}

/// Main thread playlist getter for backward compatibility
func getPlaylist(named playlistName: String, context: NSManagedObjectContext) -> MockPlaylist {
    return getPlaylistThreadSafe(named: playlistName, context: context)
}

/// Mock playlist structure for backward compatibility
struct MockPlaylist {
    let episodeIdArray: [String]
}
