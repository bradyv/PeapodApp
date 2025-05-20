//
//  QueueManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-18.
//

import SwiftUI
import CoreData
import Combine

final class QueueManager: ObservableObject {
    static let shared = QueueManager()
    
    // In-memory queue for immediate UI updates
    @Published private(set) var episodes: [Episode] = []
    
    // Background context for all Core Data operations
    private let backgroundContext: NSManagedObjectContext
    private let queueLock = NSLock()
    
    private init() {
        // Create dedicated background context
        self.backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        self.backgroundContext.parent = PersistenceController.shared.container.viewContext
        
        // Disable automatic merging to prevent background publishing warnings
        self.backgroundContext.automaticallyMergesChangesFromParent = false
        
        // Load initial queue
        loadQueue()
    }
    
    // MARK: - Public Interface
    
    /// Add episode to front of queue (for playback start)
    func addToFront(_ episode: Episode, pushingBack previousEpisode: Episode? = nil) {
        // Update UI immediately on main thread with animation
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.3)) {
                self.updateUIQueue { episodes in
                    // Remove episode if already in queue
                    episodes.removeAll { $0.id == episode.id }
                    
                    // Handle previous episode
                    if let previous = previousEpisode, previous.id != episode.id {
                        // Remove previous from its current position
                        episodes.removeAll { $0.id == previous.id }
                        // Insert at position 1 (or 0 if queue was empty)
                        if episodes.isEmpty {
                            episodes.append(previous)
                        } else {
                            episodes.insert(previous, at: 1)
                        }
                    }
                    
                    // Insert new episode at front
                    episodes.insert(episode, at: 0)
                }
            }
        }
        
        // Persist in background
        persistQueueOperation { [weak self] in
            self?.persistAddToFront(episode, pushingBack: previousEpisode)
        }
    }
    
    /// Toggle episode in queue
    func toggle(_ episode: Episode) {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.3)) {
                self.updateUIQueue { episodes in
                    if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
                        episodes.remove(at: index)
                    } else {
                        episodes.append(episode)
                    }
                }
            }
        }
        
        persistQueueOperation { [weak self] in
            self?.persistToggle(episode)
        }
    }
    
    /// Remove episode from queue
    func remove(_ episode: Episode) {
        Task { @MainActor in
            withAnimation(.spring(duration: 0.3)) {
                self.updateUIQueue { episodes in
                    episodes.removeAll { $0.id == episode.id }
                }
            }
        }
        
        persistQueueOperation { [weak self] in
            self?.persistRemove(episode)
        }
    }
    
    /// Move episode to specific position
    func move(_ episode: Episode, to position: Int) {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.3)) {
                self.updateUIQueue { episodes in
                    episodes.removeAll { $0.id == episode.id }
                    let safePosition = min(max(0, position), episodes.count)
                    episodes.insert(episode, at: safePosition)
                }
            }
        }
        
        persistQueueOperation { [weak self] in
            self?.persistMove(episode, to: position)
        }
    }
    
    /// Reorder entire queue
    func reorder(_ newOrder: [Episode]) {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.3)) {
                self.episodes = newOrder
            }
        }
        
        persistQueueOperation { [weak self] in
            self?.persistReorder(newOrder)
        }
    }
    
    // MARK: - UI Update Helper
    
    @MainActor
    private func updateUIQueue(_ operation: (inout [Episode]) -> Void) {
        var mutableEpisodes = episodes
        operation(&mutableEpisodes)
        episodes = mutableEpisodes
    }
    
    // MARK: - Queue Loading
    
    private func loadQueue() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            let episodes = await self.fetchQueueFromCoreData()
            
            await MainActor.run {
                self.episodes = episodes
            }
        }
    }
    
    private func fetchQueueFromCoreData() async -> [Episode] {
        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                do {
                    let request: NSFetchRequest<Episode> = Episode.fetchRequest()
                    request.predicate = NSPredicate(format: "isQueued == YES")
                    request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.queuePosition, ascending: true)]
                    
                    let result = try self.backgroundContext.fetch(request)
                    continuation.resume(returning: result)
                } catch {
                    print("Failed to fetch queue: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    // MARK: - Persistence Operations
    
    private func persistQueueOperation(_ operation: @escaping () -> Void) {
        Task.detached(priority: .utility) {
            await self.performBackgroundOperation(operation)
        }
    }
    
    private func performBackgroundOperation(_ operation: @escaping () -> Void) async {
        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                self.queueLock.lock()
                defer { self.queueLock.unlock() }
                
                operation()
                
                // Save background context
                do {
                    try self.backgroundContext.save()
                    
                    // Manually merge changes on main thread to avoid publishing warning
                    DispatchQueue.main.async {
                        do {
                            // Refresh any objects that might have changed
                            PersistenceController.shared.container.viewContext.refreshAllObjects()
                            try PersistenceController.shared.container.viewContext.save()
                            continuation.resume()
                        } catch {
                            print("❌ Failed to save to persistent store: \(error)")
                            continuation.resume()
                        }
                    }
                } catch {
                    print("Failed to save queue changes: \(error)")
                    self.backgroundContext.rollback()
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Core Data Persistence Methods
    
    private func persistAddToFront(_ episode: Episode, pushingBack previousEpisode: Episode?) {
        guard let bgEpisode = getBackgroundEpisode(episode) else { return }
        
        // Get queue playlist
        let queuePlaylist = getOrCreateQueuePlaylist()
        
        // Add episode to Core Data relationship if not already there
        if !bgEpisode.isQueued {
            bgEpisode.isQueued = true
            queuePlaylist.addToItems(bgEpisode)
            
            // Clear saved state when adding to queue
            if bgEpisode.isSaved {
                bgEpisode.isSaved = false
                bgEpisode.savedDate = nil
                print("✅ Cleared saved state for episode added to queue: \(bgEpisode.title ?? "Episode")")
            }
        }
        
        // Set position to 0
        bgEpisode.queuePosition = 0
        
        // Handle previous episode
        if let previous = previousEpisode,
           let bgPrevious = getBackgroundEpisode(previous),
           bgPrevious.id != bgEpisode.id {
            
            if !bgPrevious.isQueued {
                bgPrevious.isQueued = true
                queuePlaylist.addToItems(bgPrevious)
                
                // Clear saved state for previous episode too
                if bgPrevious.isSaved {
                    bgPrevious.isSaved = false
                    bgPrevious.savedDate = nil
                    print("✅ Cleared saved state for previous episode added to queue: \(bgPrevious.title ?? "Episode")")
                }
            }
            bgPrevious.queuePosition = 1
        }
        
        // Shift all other episodes down
        shiftEpisodesDown(excluding: [bgEpisode.id, previousEpisode?.id].compactMap { $0 })
    }
    
    private func persistToggle(_ episode: Episode) {
        guard let bgEpisode = getBackgroundEpisode(episode) else { return }
        
        let queuePlaylist = getOrCreateQueuePlaylist()
        
        if bgEpisode.isQueued {
            // Remove from queue
            bgEpisode.isQueued = false
            bgEpisode.queuePosition = -1
            queuePlaylist.removeFromItems(bgEpisode)
            reindexQueue()
        } else {
            // Add to end of queue
            let maxPosition = getMaxQueuePosition()
            bgEpisode.isQueued = true
            bgEpisode.queuePosition = maxPosition + 1
            queuePlaylist.addToItems(bgEpisode)
            
            // Clear saved state when adding to queue
            if bgEpisode.isSaved {
                bgEpisode.isSaved = false
                bgEpisode.savedDate = nil
                print("✅ Cleared saved state for episode added to queue: \(bgEpisode.title ?? "Episode")")
            }
        }
    }
    
    private func persistRemove(_ episode: Episode) {
        guard let bgEpisode = getBackgroundEpisode(episode) else { return }
        
        if bgEpisode.isQueued {
            let queuePlaylist = getOrCreateQueuePlaylist()
            bgEpisode.isQueued = false
            bgEpisode.queuePosition = -1
            queuePlaylist.removeFromItems(bgEpisode)
            reindexQueue()
        }
    }
    
    private func persistMove(_ episode: Episode, to position: Int) {
        guard let bgEpisode = getBackgroundEpisode(episode) else { return }
        
        let queuePlaylist = getOrCreateQueuePlaylist()
        
        if !bgEpisode.isQueued {
            bgEpisode.isQueued = true
            queuePlaylist.addToItems(bgEpisode)
            
            // Clear saved state when adding to queue
            if bgEpisode.isSaved {
                bgEpisode.isSaved = false
                bgEpisode.savedDate = nil
                print("✅ Cleared saved state for episode added to queue: \(bgEpisode.title ?? "Episode")")
            }
        }
        
        bgEpisode.queuePosition = Int64(position)
        reindexQueue()
    }
    
    private func persistReorder(_ newOrder: [Episode]) {
        let queuePlaylist = getOrCreateQueuePlaylist()
        
        for (index, episode) in newOrder.enumerated() {
            guard let bgEpisode = getBackgroundEpisode(episode) else { continue }
            
            if !bgEpisode.isQueued {
                bgEpisode.isQueued = true
                queuePlaylist.addToItems(bgEpisode)
                
                // Clear saved state when adding to queue
                if bgEpisode.isSaved {
                    bgEpisode.isSaved = false
                    bgEpisode.savedDate = nil
                    print("✅ Cleared saved state for episode added to queue: \(bgEpisode.title ?? "Episode")")
                }
            }
            
            bgEpisode.queuePosition = Int64(index)
        }
    }
    
    // MARK: - Core Data Helpers
    
    private func getBackgroundEpisode(_ episode: Episode) -> Episode? {
        do {
            return try backgroundContext.existingObject(with: episode.objectID) as? Episode
        } catch {
            print("Failed to get background episode: \(error)")
            return nil
        }
    }
    
    private func getOrCreateQueuePlaylist() -> Playlist {
        let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", "Queue")
        
        if let existing = try? backgroundContext.fetch(request).first {
            return existing
        } else {
            let playlist = Playlist(context: backgroundContext)
            playlist.name = "Queue"
            return playlist
        }
    }
    
    private func shiftEpisodesDown(excluding excludedIDs: [String]) {
        do {
            let request: NSFetchRequest<Episode> = Episode.fetchRequest()
            request.predicate = NSPredicate(format: "isQueued == YES")
            
            let queuedEpisodes = try backgroundContext.fetch(request)
            
            for episode in queuedEpisodes {
                guard let episodeID = episode.id,
                      !excludedIDs.contains(episodeID),
                      episode.queuePosition >= 0 else { continue }
                
                episode.queuePosition += 1
            }
        } catch {
            print("Failed to shift episodes: \(error)")
        }
    }
    
    private func reindexQueue() {
        do {
            let request: NSFetchRequest<Episode> = Episode.fetchRequest()
            request.predicate = NSPredicate(format: "isQueued == YES")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.queuePosition, ascending: true)]
            
            let queuedEpisodes = try backgroundContext.fetch(request)
            
            for (index, episode) in queuedEpisodes.enumerated() {
                episode.queuePosition = Int64(index)
            }
        } catch {
            print("Failed to reindex queue: \(error)")
        }
    }
    
    private func getMaxQueuePosition() -> Int64 {
        do {
            let request: NSFetchRequest<Episode> = Episode.fetchRequest()
            request.predicate = NSPredicate(format: "isQueued == YES")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.queuePosition, ascending: false)]
            request.fetchLimit = 1
            
            let result = try backgroundContext.fetch(request)
            return result.first?.queuePosition ?? -1
        } catch {
            print("Failed to get max position: \(error)")
            return -1
        }
    }
}

// MARK: - Convenience Methods

extension QueueManager {
    var isEmpty: Bool { episodes.isEmpty }
    var count: Int { episodes.count }
    var first: Episode? { episodes.first }
    
    func contains(_ episode: Episode) -> Bool {
        episodes.contains { $0.id == episode.id }
    }
    
    func position(of episode: Episode) -> Int? {
        episodes.firstIndex { $0.id == episode.id }
    }
}
