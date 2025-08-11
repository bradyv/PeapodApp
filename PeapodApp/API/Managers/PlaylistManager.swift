//
//  PlaylistManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-08-10.
//

import SwiftUI
import CoreData

// MARK: - Playlist Extensions

extension Playlist {
    // Helper to get/set episode IDs
    var episodeIdArray: [String] {
        get {
            guard let data = episodeIds,
                  let ids = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return ids
        }
        set {
            episodeIds = try? JSONEncoder().encode(newValue)
        }
    }
    
    // Check if playlist contains episode
    func containsEpisode(id: String) -> Bool {
        return episodeIdArray.contains(id)
    }
    
    // Add episode ID to playlist
    func addEpisodeId(_ episodeId: String) {
        var ids = episodeIdArray
        if !ids.contains(episodeId) {
            ids.append(episodeId)
            episodeIdArray = ids
        }
    }
    
    // Remove episode ID from playlist
    func removeEpisodeId(_ episodeId: String) {
        episodeIdArray = episodeIdArray.filter { $0 != episodeId }
    }
}

// MARK: - Episode Extensions

extension Episode {
    // Computed properties based on playlist membership
    var isQueued: Bool {
        guard let episodeId = id else { return false }
        return getPlaylistForEpisode(named: "Queue").containsEpisode(id: episodeId)
    }
    
    var isPlayed: Bool {
        guard let episodeId = id else { return false }
        return getPlaylistForEpisode(named: "Played").containsEpisode(id: episodeId)
    }
    
    var isFav: Bool {
        guard let episodeId = id else { return false }
        return getPlaylistForEpisode(named: "Favorites").containsEpisode(id: episodeId)
    }
    
    // Helper to get playlist from context
    private func getPlaylistForEpisode(named name: String) -> Playlist {
        let context = managedObjectContext ?? PersistenceController.shared.container.viewContext
        return getPlaylist(named: name, context: context)
    }
    
    // Helper to get the associated podcast
    var podcast: Podcast? {
        guard let podcastId = podcastId else { return nil }
        
        let context = managedObjectContext ?? PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", podcastId)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    // Get or create playback state for this episode
    var playbackState: Playback? {
        guard let episodeId = id else { return nil }
        
        let context = managedObjectContext ?? PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Playback> = Playback.fetchRequest()
        request.predicate = NSPredicate(format: "episodeId == %@", episodeId)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    // Get or create playback state, creating if needed
    func getOrCreatePlaybackState() -> Playback {
        if let existing = playbackState {
            return existing
        }
        
        let context = managedObjectContext ?? PersistenceController.shared.container.viewContext
        let newPlayback = Playback(context: context)
        newPlayback.episodeId = self.id // This works now!
        return newPlayback
    }
    
    // Convenience properties that delegate to Playback entity
    var queuePosition: Int64 {
        get { playbackState?.queuePosition ?? -1 }
        set { getOrCreatePlaybackState().queuePosition = newValue }
    }
    
    var playbackPosition: Double {
        get { playbackState?.playbackPosition ?? 0.0 }
        set { getOrCreatePlaybackState().playbackPosition = newValue }
    }
    
    var playCount: Int64 {
        get { playbackState?.playCount ?? 0 }
        set { getOrCreatePlaybackState().playCount = newValue }
    }
    
    var playedDate: Date? {
        get { playbackState?.playedDate }
        set { getOrCreatePlaybackState().playedDate = newValue }
    }
    
    var favDate: Date? {
        get { playbackState?.favDate }
        set { getOrCreatePlaybackState().favDate = newValue }
    }
}

// MARK: - Playlist Management Functions

func getPlaylist(named name: String, context: NSManagedObjectContext) -> Playlist {
    let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", name)
    
    if let existingPlaylist = try? context.fetch(request).first {
        return existingPlaylist
    } else {
        let newPlaylist = Playlist(context: context)
        newPlaylist.name = name
        newPlaylist.id = UUID()
        newPlaylist.episodeIdArray = [] // Initialize empty array
        try? context.save()
        return newPlaylist
    }
}

func addEpisodeToPlaylist(_ episode: Episode, playlistName: String) {
    guard let context = episode.managedObjectContext,
          let episodeId = episode.id else { return }
    
    let playlist = getPlaylist(named: playlistName, context: context)
    
    // Check if episode is already in this playlist
    if !playlist.containsEpisode(id: episodeId) {
        playlist.addEpisodeId(episodeId)
        
        // Set special properties for certain playlists
        if playlistName == "Played" {
            episode.playedDate = Date()
        } else if playlistName == "Favorites" {
            episode.favDate = Date()
        }
        
        try? context.save()
    }
}

func removeEpisodeFromPlaylist(_ episode: Episode, playlistName: String) {
    guard let context = episode.managedObjectContext,
          let episodeId = episode.id else { return }
    
    let playlist = getPlaylist(named: playlistName, context: context)
    
    if playlist.containsEpisode(id: episodeId) {
        playlist.removeEpisodeId(episodeId)
        
        // Clear special properties for certain playlists
        if playlistName == "Played" {
            episode.playedDate = nil
            episode.playbackPosition = 0
        } else if playlistName == "Favorites" {
            episode.favDate = nil
        }
        
        try? context.save()
    }
}

// MARK: - Fetch Episodes by Playlist

func fetchEpisodesInPlaylist(named playlistName: String, context: NSManagedObjectContext) -> [Episode] {
    let playlist = getPlaylist(named: playlistName, context: context)
    let episodeIds = playlist.episodeIdArray
    
    guard !episodeIds.isEmpty else { return [] }
    
    let request: NSFetchRequest<Episode> = Episode.fetchRequest()
    request.predicate = NSPredicate(format: "id IN %@", episodeIds)
    
    do {
        let episodes = try context.fetch(request)
        
        // For queue, maintain order based on queuePosition
        if playlistName == "Queue" {
            return episodes.sorted { $0.queuePosition < $1.queuePosition }
        }
        // For others, sort by air date (newest first)
        else {
            return episodes.sorted { ($0.airDate ?? Date.distantPast) > ($1.airDate ?? Date.distantPast) }
        }
    } catch {
        LogManager.shared.error("❌ Error fetching episodes for playlist \(playlistName): \(error)")
        return []
    }
}
