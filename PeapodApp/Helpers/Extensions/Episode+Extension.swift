//
//  Episode+Extension.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-06-02.
//

import Foundation
import CoreData

extension Episode {
    // MARK: - Playback State Management
    
    /// Get or create playback state for this episode
    var playbackState: Playback? {
        guard let episodeId = id else { return nil }
        
        let context = managedObjectContext ?? PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Playback> = Playback.fetchRequest()
        request.predicate = NSPredicate(format: "episodeId == %@", episodeId)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    /// Get or create playback state, creating if needed
    func getOrCreatePlaybackState() -> Playback {
        if let existing = playbackState {
            return existing
        }
        
        let context = managedObjectContext ?? PersistenceController.shared.container.viewContext
        let newPlayback = Playback(context: context)
        newPlayback.episodeId = self.id
        return newPlayback
    }
    
    // MARK: - Boolean Properties (Main Interface)
    
    var isQueued: Bool {
        get { playbackState?.isQueued ?? false }
        set {
            let playback = getOrCreatePlaybackState()
            playback.isQueued = newValue
            if newValue {
                // Set queue position when adding to queue
                playback.queuePosition = nextQueuePosition()
            } else {
                playback.queuePosition = -1
            }
        }
    }
    
    var isPlayed: Bool {
        get { playbackState?.isPlayed ?? false }
        set {
            let playback = getOrCreatePlaybackState()
            playback.isPlayed = newValue
            if newValue {
                playback.playedDate = Date()
            } else {
                playback.playedDate = nil
                playback.playbackPosition = 0
            }
        }
    }
    
    var isFav: Bool {
        get { playbackState?.isFav ?? false }
        set {
            let playback = getOrCreatePlaybackState()
            playback.isFav = newValue
            if newValue {
                playback.favDate = Date()
            } else {
                playback.favDate = nil
            }
        }
    }
    
    // MARK: - Convenience Properties (Delegated to Playback)
    
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
    
    // MARK: - Helper Functions
    
    private func nextQueuePosition() -> Int64 {
        let context = managedObjectContext ?? PersistenceController.shared.container.viewContext
        return getNextQueuePosition(context: context)
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
}
