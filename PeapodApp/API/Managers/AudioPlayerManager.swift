//
//  AudioPlayerManager.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-05.
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import CoreData
import Kingfisher
import UIKit

// MARK: - Unified Playback State
struct PlaybackState: Equatable {
    let episode: Episode?
    let position: Double
    let duration: Double
    let isPlaying: Bool
    let isLoading: Bool
    
    var episodeID: String? { episode?.id }
    
    static let idle = PlaybackState(episode: nil, position: 0, duration: 0, isPlaying: false, isLoading: false)
    
    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        return lhs.episodeID == rhs.episodeID &&
               abs(lhs.position - rhs.position) < 0.1 &&
               abs(lhs.duration - rhs.duration) < 0.1 &&
               lhs.isPlaying == rhs.isPlaying &&
               lhs.isLoading == rhs.isLoading
    }
}

private var viewContext: NSManagedObjectContext {
    PersistenceController.shared.container.viewContext
}

func fetchQueuedEpisodes() -> [Episode] {
    let context = PersistenceController.shared.container.viewContext
    return getQueuedEpisodes(context: context)
}

class AudioPlayerManager: ObservableObject, @unchecked Sendable {
    static let shared = AudioPlayerManager()
    
    // MARK: - Single Source of Truth
    @Published private(set) var playbackState = PlaybackState.idle {
        didSet {
            if playbackState != oldValue {
                updateNowPlayingInfo()
            }
        }
    }
    
    // MARK: - Simplified State Intent
    private var userInitiatedPause = false
    
    // MARK: - Episode Keys
    private let currentEpisodeKey = "currentEpisodeID"
    private let currentPositionKey = "currentPosition"
    
    // MARK: - Computed Properties (derived from playbackState)
    var currentEpisode: Episode? { playbackState.episode }
    var progress: Double { playbackState.position }
    var isPlaying: Bool { playbackState.isPlaying }
    var isLoading: Bool { playbackState.isLoading }
    
    // MARK: - Player and Settings
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerObservations: [NSKeyValueObservation] = []
    private var positionSaveTimer: Timer?
    private var lastSavedPosition: Double = 0
    private let queueLock = NSLock()
    private var cachedArtwork: MPMediaItemArtwork?
    private var positionUpdateWorkItem: DispatchWorkItem?
    
    @Published var playbackSpeed: Float = UserDefaults.standard.float(forKey: "playbackSpeed").nonZeroOrDefault(1.0) {
        didSet {
            UserDefaults.standard.set(playbackSpeed, forKey: "playbackSpeed")
            player?.rate = isPlaying ? playbackSpeed : 0.0
            updateNowPlayingInfo()
        }
    }
    
    @Published var forwardInterval: Double = UserDefaults.standard.double(forKey: "forwardInterval") != 0 ? UserDefaults.standard.double(forKey: "forwardInterval") : 30 {
        didSet {
            UserDefaults.standard.set(forwardInterval, forKey: "forwardInterval")
            updateRemoteCommandIntervals()
        }
    }
    
    @Published var backwardInterval: Double = UserDefaults.standard.double(forKey: "backwardInterval") != 0 ? UserDefaults.standard.double(forKey: "backwardInterval") : 15 {
        didSet {
            UserDefaults.standard.set(backwardInterval, forKey: "backwardInterval")
            updateRemoteCommandIntervals()
        }
    }
    
    @Published var autoplayNext: Bool = UserDefaults.standard.bool(forKey: "autoplayNext") {
        didSet {
            UserDefaults.standard.set(autoplayNext, forKey: "autoplayNext")
        }
    }
    
    @Published var isSeekingManually: Bool = false
    
    private init() {
        primePlayer()
        configureRemoteTransportControls()
        updateRemoteCommandIntervals()
        setupNotifications()
        restoreCurrentEpisodeState()
    }
    
    // MARK: - State Management
    private func updateState(episode: Episode? = nil, position: Double? = nil, duration: Double? = nil, isPlaying: Bool? = nil, isLoading: Bool? = nil) {
        let newState = PlaybackState(
            episode: episode ?? playbackState.episode,
            position: position ?? playbackState.position,
            duration: duration ?? playbackState.duration,
            isPlaying: isPlaying ?? playbackState.isPlaying,
            isLoading: isLoading ?? playbackState.isLoading
        )
        
        playbackState = newState
        
        // Save current episode state when it changes
        saveCurrentEpisodeState()
    }
    
    private func clearState() {
        LogManager.shared.info("Clearing episode from state: \(playbackState.episode?.title?.prefix(20) ?? "nil") -> nil")
        playbackState = PlaybackState.idle
        saveCurrentEpisodeState()
    }
    
    private func saveCurrentEpisodeState() {
        if let episode = playbackState.episode {
            UserDefaults.standard.set(episode.id, forKey: currentEpisodeKey)
            UserDefaults.standard.set(playbackState.position, forKey: currentPositionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentEpisodeKey)
            UserDefaults.standard.removeObject(forKey: currentPositionKey)
        }
    }

    // Add this function to restore current episode
    private func restoreCurrentEpisodeState() {
        guard let episodeID = UserDefaults.standard.string(forKey: currentEpisodeKey) else { return }
        
        // Find the episode in Core Data
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND nowPlaying == YES", episodeID)
        request.fetchLimit = 1
        
        do {
            if let episode = try viewContext.fetch(request).first {
                let savedPosition = UserDefaults.standard.double(forKey: currentPositionKey)
                let duration = getActualDuration(for: episode)
                
                // Restore the playback state without starting playback
                updateState(episode: episode, position: savedPosition, duration: duration, isPlaying: false, isLoading: false)
                
                LogManager.shared.info("Restored current episode: \(episode.title?.prefix(30) ?? "Episode")")
            } else {
                // Episode not found or not marked as nowPlaying - clear the saved state
                UserDefaults.standard.removeObject(forKey: currentEpisodeKey)
                UserDefaults.standard.removeObject(forKey: currentPositionKey)
            }
        } catch {
            LogManager.shared.error("Failed to restore current episode: \(error)")
        }
    }
    
    // MARK: - Core Playback Control
    func togglePlayback(for episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
        guard let episodeID = episode.id else { return }
        
        LogManager.shared.info("Toggle playback for: \(episode.title?.prefix(30) ?? "Episode")")
        
        // Handle current episode
        if let currentEpisode = playbackState.episode, currentEpisode.id == episodeID {
            if playbackState.isPlaying {
                pause()
            } else if playbackState.isLoading {
                LogManager.shared.info("Already loading - ignoring")
            } else {
                userInitiatedPause = false
                resume()
            }
            return
        }
        
        // Start new episode
        userInitiatedPause = false
        startPlayback(for: episode, episodesViewModel: episodesViewModel)
    }
    
    private func startPlayback(for episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
        guard let episodeID = episode.id,
              let audioURL = episode.audio,
              !audioURL.isEmpty,
              let url = URL(string: audioURL) else {
            LogManager.shared.error("Invalid episode data")
            return
        }
        
        // Add to queue SYNCHRONOUSLY if not already queued
        if !episode.isQueued {
            episode.isQueued = true
            episode.objectWillChange.send()
            
            // Update the episodes view model immediately
            Task { @MainActor in
                episodesViewModel?.fetchQueue()
            }
            
            // Save to Core Data
            do {
                try episode.managedObjectContext?.save()
            } catch {
                LogManager.shared.error("Failed to add episode to queue: \(error)")
                episode.isQueued = false // Revert on failure
            }
        }
        
        // Get saved position and duration
        let savedPosition = episode.playbackPosition
        let duration = getActualDuration(for: episode)
        
        // Update state to loading
        updateState(episode: episode, position: savedPosition, duration: duration, isPlaying: false, isLoading: true)
        
        Task.detached(priority: .userInitiated) {
            await self.setupPlayer(url: url, episode: episode, startPosition: savedPosition)
        }
    }
    
    private func setupPlayer(url: URL, episode: Episode, startPosition: Double) async {
        guard let episodeID = episode.id else { return }

        // Step 1: on MainActor, cleanup and allocate
        await MainActor.run {
            self.cleanupPlayer()
            self.cachedArtwork = nil

            let playerItem = AVPlayerItem(url: url)
            self.player = AVPlayer(playerItem: playerItem)
            // Initially disable stalling, we’ll override next
            self.player?.automaticallyWaitsToMinimizeStalling = false

            self.setupPlayerObservations(for: episodeID)
        }

        // Step 2: Seek if needed
        if startPosition > 0 {
            await seekToPosition(startPosition)
        }

        // Step 3: Activate audio session before playback attempt
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            LogManager.shared.info("Audio session successfully activated")
        } catch {
            LogManager.shared.error("Failed to activate audio session: \(error)")
            // You might want to retry or delay here
        }

        // Step 4: Choose stalling strategy based on state
        let isInBackground = UIApplication.shared.applicationState == .background
        await MainActor.run {
            self.player?.automaticallyWaitsToMinimizeStalling = isInBackground
        }

        // Step 5: Start playback
        await MainActor.run {
            if isInBackground {
                // In background, prefer letting the system buffer first
                self.player?.play()
            } else {
                // In foreground, you can go aggressive
                self.player?.play()
                self.player?.rate = self.playbackSpeed
            }
        }

        // Step 6: As a fallback, try playImmediately if things didn’t start
        // (Optional) after a small delay, check if playing, and if not, force immediate play
        Task { @MainActor in
            try await Task.sleep(nanoseconds: UInt64(0.5 * Double(NSEC_PER_SEC)))
            if let p = self.player, p.rate == 0 {
                LogManager.shared.warning("Playback not started; trying playImmediately")
                p.playImmediately(atRate: self.playbackSpeed)
            }
        }

        // Step 7: Now the rest of your “mark nowPlaying state, update metadata, etc.”
        await MainActor.run {
            episode.nowPlaying = true
            if episode.isPlayed {
                removeEpisodeFromPlaylist(episode, playlistName: "Played")
            }
            if !episode.isQueued {
                episode.isQueued = true
            }
            try? episode.managedObjectContext?.save()

            MPNowPlayingInfoCenter.default().playbackState = .playing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.updateNowPlayingInfo()
            }
        }
    }
    
    private func pause() {
        guard let player = player else { return }
        
        // Mark as user-initiated pause
        userInitiatedPause = true
        
        player.pause()
        updateState(isPlaying: false, isLoading: false)
        
        // Save position immediately on pause
        if let episode = playbackState.episode {
            savePositionImmediately(for: episode, position: playbackState.position)
        }
    }
    
    private func resume() {
        guard let player = player,
              let currentItem = player.currentItem,
              currentItem.status == .readyToPlay else {
            // No valid player/item - restart playback
            if let episode = playbackState.episode {
                LogManager.shared.info("No valid player for resume - restarting playback")
                userInitiatedPause = false
                Task { @MainActor in
                    await startPlayback(for: episode)
                }
            }
            return
        }
        
        // Valid player exists, just resume
        userInitiatedPause = false
        player.rate = playbackSpeed
    }
    
    func stop() {
        // Save final position
        if let episode = playbackState.episode {
            savePositionImmediately(for: episode, position: playbackState.position)
            episode.nowPlaying = false
            try? episode.managedObjectContext?.save()
        }
        
        cleanupPlayer()
        
        // CRITICAL: Completely clear the playback state
        clearState()
        
        // Clear system now playing
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        LogManager.shared.info("Player stopped and state cleared")
    }
    
    // MARK: - Player Observations
    private func setupPlayerObservations(for episodeID: String) {
        guard let player = player else { return }
        
        // Clean up previous observations
        playerObservations.forEach { $0.invalidate() }
        playerObservations.removeAll()
        
        // Rate observer - simplified logic
        let rateObserver = player.observe(\.rate, options: [.new]) { [weak self] _, change in
            guard let self = self else { return }
            
            let newRate = change.newValue ?? 0
            
            DispatchQueue.main.async {
                guard self.playbackState.episodeID == episodeID else { return }
                
                // Simple: just reflect what the system is doing
                let isPlaying = newRate > 0
                self.updateState(isPlaying: isPlaying, isLoading: false)
            }
        }
        playerObservations.append(rateObserver)
        
        // Time observer (for position updates)
        let interval = UIApplication.shared.applicationState == .background ? 3.0 : 1.0
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 10),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            
            // Only update if this is still the current episode
            guard self.playbackState.episodeID == episodeID,
                  !self.isSeekingManually else { return }
            
            let newPosition = time.seconds
            guard newPosition.isFinite && newPosition >= 0 else { return }
            
            // DEBOUNCE: Cancel previous update and schedule new one
            self.positionUpdateWorkItem?.cancel()
            self.positionUpdateWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                
                // Check if player actually stopped (rate = 0) but we're still near the end
                let playerRate = self.player?.rate ?? 0
                let duration = self.playbackState.duration
                let isNearEnd = duration > 0 && newPosition >= (duration - 3.0)
                let hasValidDuration = duration > 10
                
                // Episode completion detection
                if isNearEnd && hasValidDuration && playerRate == 0 && self.playbackState.isPlaying {
                    LogManager.shared.info("Background episode completion detected")
                    self.handleEpisodeEnd()
                    return
                }
                
                if isNearEnd && hasValidDuration && playerRate > 0 {
                    LogManager.shared.info("Foreground episode ending detected")
                    self.handleEpisodeEnd()
                    return
                }
                
                // Only update if position actually changed significantly
                if abs(newPosition - self.playbackState.position) > 0.5 {
                    self.updateState(position: newPosition)
                }
            }
            
            // Execute after a small delay to debounce rapid updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: self.positionUpdateWorkItem!)
        }
        
        // Status observer (for errors/ready state)
        if let currentItem = player.currentItem {
            let statusObserver = currentItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    guard self.playbackState.episodeID == episodeID else { return }
                    
                    switch item.status {
                    case .readyToPlay:
                        // Update duration only
                        let duration = item.asset.duration.seconds
                        if duration.isFinite && duration > 0 {
                            self.updateState(duration: duration)
                            
                            if let episode = self.playbackState.episode, episode.actualDuration <= 0 {
                                episode.actualDuration = duration
                                try? episode.managedObjectContext?.save()
                            }
                        }
                    case .failed:
                        // Just log and stop - don't try to recover
                        LogManager.shared.error("Player failed: \(item.error?.localizedDescription ?? "unknown")")
                        self.updateState(isPlaying: false, isLoading: false)
                    default:
                        break
                    }
                }
            }
            playerObservations.append(statusObserver)
            
            // Player item ended notification observer
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: currentItem,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                guard self.playbackState.episodeID == episodeID else { return }
                
                LogManager.shared.info("AVPlayerItemDidPlayToEndTime notification received")
                // Small delay to ensure any final time updates are processed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.handleEpisodeEnd()
                }
            }
            
            // Player stalled notification (backup detection)
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: currentItem,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                guard self.playbackState.episodeID == episodeID else { return }
                
                // Check if we stalled near the end (might be completion)
                let currentTime = self.player?.currentTime().seconds ?? 0
                let duration = self.playbackState.duration
                
                if duration > 0 && currentTime >= (duration - 10.0) && duration > 10 {
                    LogManager.shared.info("Player stalled near end - checking for completion: pos=\(currentTime), duration=\(duration)")
                    
                    // Wait a moment and check if we're actually at the end
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let finalTime = self.player?.currentTime().seconds ?? 0
                        if finalTime >= (duration - 5.0) {
                            LogManager.shared.info("Confirmed episode completion via stall detection")
                            self.handleEpisodeEnd()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Position Management
    private func savePositionIfNeeded() {
        guard let episode = playbackState.episode else { return }
        
        let currentPos = playbackState.position
        
        // Save throttled for regular updates (every 2 seconds)
        if abs(currentPos - lastSavedPosition) >= 2.0 {
            positionSaveTimer?.invalidate()
            positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.savePositionToDatabase(for: episode, position: currentPos)
            }
        }
    }
    
    private func savePositionImmediately(for episode: Episode, position: Double) {
        lastSavedPosition = position
        episode.playbackPosition = position
        try? episode.managedObjectContext?.save()
        LogManager.shared.info("Saved position immediately: \(String(format: "%.1f", position))")
    }
    
    private func savePositionToDatabase(for episode: Episode, position: Double) {
        lastSavedPosition = position
        
        let objectID = episode.objectID
        Task.detached(priority: .background) {
            let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
            backgroundContext.perform {
                do {
                    if let episodeInBackground = try backgroundContext.existingObject(with: objectID) as? Episode {
                        episodeInBackground.playbackPosition = position
                        if backgroundContext.hasChanges {
                            try backgroundContext.save()
                            LogManager.shared.info("Background saved position: \(String(format: "%.1f", position))")
                        }
                    }
                } catch {
                    LogManager.shared.error("Failed to save position: \(error)")
                }
            }
        }
    }
    
    private func saveCurrentPosition() async {
        guard let episode = playbackState.episode else { return }
        
        await MainActor.run {
            self.savePositionImmediately(for: episode, position: self.playbackState.position)
        }
    }
    
    // MARK: - Now Playing Info (Auto-synced)
    private func updateNowPlayingInfo() {
        guard let episode = playbackState.episode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title ?? "Episode",
            MPMediaItemPropertyArtist: episode.podcast?.title ?? "Podcast",
            MPNowPlayingInfoPropertyPlaybackRate: playbackState.isPlaying ? playbackSpeed : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playbackState.position,
            MPMediaItemPropertyPlaybackDuration: playbackState.duration,
            MPNowPlayingInfoPropertyMediaType: 1
        ]
        
        if let cachedArtwork = cachedArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = cachedArtwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        } else {
            fetchArtwork(for: episode) { artwork in
                DispatchQueue.main.async {
                    if let artwork = artwork {
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            }
        }
    }
    
    // MARK: - Seeking
    func seek(to time: Double) {
        guard let player = player else { return }
        
        isSeekingManually = true
        
        // Update state immediately for responsive UI
        updateState(position: time)
        
        let targetTime = CMTime(seconds: time, preferredTimescale: 1)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            DispatchQueue.main.async {
                self?.isSeekingManually = false
                if !completed {
                    LogManager.shared.warning("Seek failed")
                }
            }
        }
    }
    
    func skipForward(seconds: Double) {
        let newPosition = min(playbackState.position + seconds, playbackState.duration)
        seek(to: newPosition)
    }
    
    func skipBackward(seconds: Double) {
        let newPosition = max(playbackState.position - seconds, 0)
        seek(to: newPosition)
    }
    
    // MARK: - Helper Functions
    private func primePlayer() {
        self.player = AVPlayer()
    }
    
    private func seekToPosition(_ position: Double) async {
        guard let player = player else { return }
        
        await withCheckedContinuation { continuation in
            let targetTime = CMTime(seconds: position, preferredTimescale: 1)
            player.seek(to: targetTime) { _ in
                continuation.resume()
            }
        }
    }
    
    private func handleEpisodeEnd() {
        guard let episode = playbackState.episode else { return }
        
        LogManager.shared.info("Episode finished: \(episode.title?.prefix(30) ?? "Episode")")
        
        let context = episode.managedObjectContext ?? viewContext
        let wasPlayed = episode.isPlayed
        
        // CRITICAL: Cancel any pending position saves FIRST and reset position immediately
        positionSaveTimer?.invalidate()
        positionSaveTimer = nil
        
        // CRITICAL: Reset position to 0 BEFORE any other operations
        episode.playbackPosition = 0
        
        // Mark as played using boolean system
        episode.isPlayed = true
        
        // Clear nowPlaying
        episode.nowPlaying = false
        
        if let podcast = episode.podcast {
            podcast.playCount += 1
            podcast.playedSeconds += playbackState.duration
        }
        
        // Remove from queue in same transaction if not already played
        if !wasPlayed {
            LogManager.shared.info("Removing finished episode from queue")
            
            Task { @MainActor in
                removeFromQueue(episode)
            }
        } else {
            LogManager.shared.info("Episode was already played - not removing from queue")
        }
        
        // Single save for all changes
        do {
            try context.save()
            LogManager.shared.info("Episode marked as played and saved with position reset to 0")
        } catch {
            LogManager.shared.error("Failed to save episode completion: \(error)")
        }
        
        // Clear player state AFTER saving (only if not already cleared by removeFromQueue)
        if playbackState.episode != nil {
            LogManager.shared.info("Clearing player state after episode completion")
            clearState()
            cleanupPlayer()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        } else {
            LogManager.shared.info("Player state already cleared by queue removal")
        }
        
        // Check for autoplay AFTER clearing state
        if autoplayNext {
            // Check premium access on main actor
            Task { @MainActor in
                guard UserManager.shared.hasPremiumAccess else { return }
                
                let queuedEpisodes = fetchQueuedEpisodes()
                if let nextEpisode = queuedEpisodes.first {
                    LogManager.shared.info("Auto-playing next episode: \(nextEpisode.title?.prefix(30) ?? "Next")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startPlayback(for: nextEpisode)
                    }
                }
            }
        }
        
        // Final queue status check
        checkQueueStatusAfterRemoval()
    }
    
    private func cleanupPlayer() {
        // Remove time observer
        timeObserver.map { player?.removeTimeObserver($0) }
        timeObserver = nil
        
        // Remove property observers
        playerObservations.forEach { $0.invalidate() }
        playerObservations.removeAll()
        
        // Stop player - don't force replaceCurrentItem
        player?.pause()
        player = nil
    }
    
    // MARK: - Public Getters (for compatibility)
    func getActualDuration(for episode: Episode) -> Double {
        // Always prefer the saved actualDuration from Core Data if it exists
        if episode.actualDuration > 0 {
            return episode.actualDuration
        }
        
        // For currently playing episode, fall back to player duration if available
        if let currentEpisode = playbackState.episode,
           currentEpisode.id == episode.id,
           playbackState.duration > 0 {
            return playbackState.duration
        }
        
        // Final fallback to feed duration
        return episode.duration
    }
    
    func getProgress(for episode: Episode) -> Double {
        if let currentEpisode = playbackState.episode, currentEpisode.id == episode.id {
            return playbackState.position
        }
        return episode.playbackPosition
    }
    
    func isPlayingEpisode(_ episode: Episode) -> Bool {
        return playbackState.episode?.id == episode.id && playbackState.isPlaying
    }
    
    func isLoadingEpisode(_ episode: Episode) -> Bool {
        return playbackState.episode?.id == episode.id && playbackState.isLoading
    }
    
    func hasStartedPlayback(for episode: Episode) -> Bool {
        return episode.playbackPosition > 0
    }
    
    func markAsPlayed(for episode: Episode, manually: Bool = false) {
        let context = episode.managedObjectContext ?? viewContext
        
        let isCurrentEpisode = (playbackState.episode?.id == episode.id)
        let progressBeforeStop = isCurrentEpisode ? playbackState.position : episode.playbackPosition
        
        // Toggle played state
        episode.isPlayed = true
        
        let actualDuration = getActualDuration(for: episode)
        let playedTime = manually ? progressBeforeStop : actualDuration
        
        if let podcast = episode.podcast {
            podcast.playCount += 1
            podcast.playedSeconds += playedTime
        }
        
        // Reset position and nowPlaying
        episode.playbackPosition = 0
        episode.nowPlaying = false
        
        // Stop playback if this is the current episode
        if isCurrentEpisode {
            positionSaveTimer?.invalidate()
            positionSaveTimer = nil
            
            LogManager.shared.info("Stopping player for manual mark as played")
            clearState()
            cleanupPlayer()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        
        do {
            try context.save()
            LogManager.shared.info("Manual mark as played completed - isPlayed: \(episode.isPlayed)")
        } catch {
            LogManager.shared.error("Failed to save manual mark as played: \(error)")
        }
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func markAsUnplayed(for episode: Episode) {
        let context = episode.managedObjectContext ?? viewContext
        
        guard episode.isPlayed else {
            return // Already unplayed, no changes needed
        }
        
        episode.isPlayed = false
        
        do {
            try context.save()
            LogManager.shared.info("Mark as unplayed completed")
        } catch {
            LogManager.shared.error("Failed to mark as unplayed: \(error)")
        }
    }

    func writeActualDuration(for episode: Episode) {
        guard episode.actualDuration <= 0,
              let urlString = episode.audio,
              let url = URL(string: urlString) else {
            return
        }
        
        let asset = AVURLAsset(url: url)
        let objectID = episode.objectID
        
        Task.detached(priority: .background) {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = duration.seconds
                
                await MainActor.run {
                    if let updatedEpisode = try? viewContext.existingObject(with: objectID) as? Episode {
                        updatedEpisode.actualDuration = durationSeconds
                        try? updatedEpisode.managedObjectContext?.save()
                        
                        // Update current state if this is the playing episode
                        if self.playbackState.episode?.id == episode.id {
                            self.updateState(duration: durationSeconds)
                        }
                    }
                }
            } catch {
                LogManager.shared.warning("Failed to load actual duration: \(error)")
            }
        }
    }
    
    // MARK: - Time Formatting
    func formatView(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%02d:%02d", minutes, remainingSeconds)
        }
    }
    
    func getElapsedTime(for episode: Episode) -> String {
        let elapsedTime = Int(getProgress(for: episode))
        return formatView(seconds: elapsedTime)
    }
    
    func getRemainingTime(for episode: Episode, pretty: Bool = true) -> String {
        let duration = getActualDuration(for: episode)
        let position = getProgress(for: episode)
        let remaining = max(0, duration - position)
        let seconds = Int(remaining)
        
        return pretty ? formatDuration(seconds: seconds) : formatView(seconds: seconds)
    }
    
    func getStableRemainingTime(for episode: Episode, pretty: Bool = true) -> String {
        let duration = getActualDuration(for: episode)
        let progress = getProgress(for: episode)
        
        // Check if this episode has ever been played (either currently or previously)
        let hasEverBeenPlayed = isPlayingEpisode(episode) ||
                               isLoadingEpisode(episode) ||
                               hasStartedPlayback(for: episode) ||
                               progress > 0
        
        let valueToShow: Double
        if hasEverBeenPlayed {
            // Always show remaining time if episode has been touched
            valueToShow = max(0, duration - progress)
        } else {
            // Show full duration for untouched episodes
            valueToShow = duration
        }
        
        let seconds = Int(valueToShow)
        return pretty ? formatDuration(seconds: seconds) : formatView(seconds: seconds)
    }
    
    // MARK: - Simplified Notifications Setup
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(savePlaybackOnExit), name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    @objc private func appDidEnterBackground() {
        // Save current state
        if let episode = playbackState.episode {
            savePositionImmediately(for: episode, position: playbackState.position)
        }
        
        LogManager.shared.info("App backgrounded - was playing: \(playbackState.isPlaying)")
    }
    
    @objc private func savePlaybackOnExit() {
        if let episode = playbackState.episode {
            savePositionImmediately(for: episode, position: playbackState.position)
        }
    }
    
    // MARK: - Remote Controls & Artwork
    private func configureRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            
            // Only resume if we have a valid player and episode
            if let episode = self.playbackState.episode {
                if self.player != nil {
                    self.resume()
                } else {
                    // User explicitly pressed play - restart is OK here
                    self.userInitiatedPause = false
                    self.startPlayback(for: episode)
                }
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [60]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.skipForward(seconds: self.forwardInterval)  // Uses current value
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.skipBackward(seconds: self.backwardInterval)  // Uses current value
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
    }
    
    private func updateRemoteCommandIntervals() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipForwardCommand.preferredIntervals = [forwardInterval as NSNumber]
        commandCenter.skipBackwardCommand.preferredIntervals = [backwardInterval as NSNumber]
    }
    
    private func fetchArtwork(for episode: Episode, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        if let cachedArtwork = cachedArtwork {
            completion(cachedArtwork)
            return
        }
        
        let imageUrls = [episode.episodeImage, episode.podcast?.image]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        
        guard let validImageUrl = imageUrls.first, let url = URL(string: validImageUrl) else {
            completion(nil)
            return
        }
        
        KingfisherManager.shared.cache.retrieveImage(forKey: url.cacheKey) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let value):
                if let cachedImage = value.image {
                    let artwork = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in cachedImage }
                    self.cachedArtwork = artwork
                    completion(artwork)
                } else {
                    self.downloadAndCacheArtwork(from: url, completion: completion)
                }
            case .failure:
                self.downloadAndCacheArtwork(from: url, completion: completion)
            }
        }
    }
    
    private func downloadAndCacheArtwork(from url: URL, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self,
                  error == nil,
                  let data = data,
                  let image = UIImage(data: data) else {
                completion(nil)
                return
            }
            
            KingfisherManager.shared.cache.store(image, forKey: url.cacheKey)
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.cachedArtwork = artwork
            completion(artwork)
        }.resume()
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        // Only update rate if currently playing
        if playbackState.isPlaying {
            player?.rate = speed
        }
    }
    
    func setForwardInterval(_ interval: Double) {
        forwardInterval = interval
    }
    
    func setBackwardInterval(_ interval: Double) {
        backwardInterval = interval
    }

    private func checkQueueStatusAfterRemoval() {
        // Check if queue is now empty and current episode should be cleared
        let queuedEpisodes = fetchQueuedEpisodes()
        
        if queuedEpisodes.isEmpty {
            // Queue is empty - check if current episode should be cleared
            if let currentEpisode = playbackState.episode, !currentEpisode.isQueued {
                LogManager.shared.warning("Queue empty and current episode not queued - clearing player state")
                stop()
            }
        }
    }

    /// Public method for global queue functions to call
    @MainActor
    func handleQueueRemoval() {
        checkQueueStatusAfterRemoval()
        
        // Notify any listening views that queue changed
        NotificationCenter.default.post(name: .episodeQueueUpdated, object: nil)
    }
    
    @MainActor
    func removeMultipleFromQueue(_ episodes: [Episode]) {
        guard !episodes.isEmpty else { return }
        guard let context = episodes.first?.managedObjectContext else { return }
        
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Immediate UI feedback for all episodes
        for episode in episodes {
            episode.objectWillChange.send()
            episode.isQueued = false
        }
        
        // Reindex remaining episodes
        let remainingEpisodes = getQueuedEpisodes(context: context)
            .sorted { $0.queuePosition < $1.queuePosition }
        
        for (index, ep) in remainingEpisodes.enumerated() {
            ep.objectWillChange.send()
            ep.queuePosition = Int64(index)
        }
        
        do {
            try context.save()
            LogManager.shared.info("Removed \(episodes.count) episodes from queue")
            
            NotificationCenter.default.post(name: .episodeQueueUpdated, object: nil)
            
        } catch {
            LogManager.shared.error("Error removing multiple episodes from queue: \(error)")
            context.rollback()
        }
        
        // Check if current episode should be stopped
        if let currentEpisode = playbackState.episode,
           episodes.contains(where: { $0.id == currentEpisode.id }) {
            handleQueueRemoval()
        }
    }

    @MainActor
    func reorderQueue(episodes: [Episode]) {
        guard !episodes.isEmpty else { return }
        guard let context = episodes.first?.managedObjectContext else { return }
        
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Update positions with immediate UI feedback
        for (index, episode) in episodes.enumerated() {
            episode.objectWillChange.send()
            episode.queuePosition = Int64(index)
        }
        
        do {
            try context.save()
            LogManager.shared.info("Reordered queue with \(episodes.count) episodes")
            
            NotificationCenter.default.post(name: .episodeQueueUpdated, object: nil)
            
        } catch {
            LogManager.shared.error("Error reordering queue: \(error)")
            context.rollback()
        }
    }

    func updateEpisodeQueuePosition(_ episode: Episode, to position: Int) {
        guard let context = episode.managedObjectContext else { return }
        
        queueLock.lock()
        defer { queueLock.unlock() }
        
        episode.objectWillChange.send()
        
        // Ensure episode is in the queue
        if !episode.isQueued {
            episode.isQueued = true
        }
        
        // Get current queue order
        let queue = getQueuedEpisodes(context: context)
            .sorted { $0.queuePosition < $1.queuePosition }
        
        // Create new ordering
        var reordered = queue.filter { $0.id != episode.id }
        let targetPosition = min(max(0, position), reordered.count)
        reordered.insert(episode, at: targetPosition)
        
        // Update positions with immediate UI feedback
        for (index, ep) in reordered.enumerated() {
            ep.objectWillChange.send()
            ep.queuePosition = Int64(index)
        }
        
        do {
            try context.save()
            LogManager.shared.info("Updated episode queue position: \(episode.title ?? "Episode") to position \(position)")
            
            Task { @MainActor in
                NotificationCenter.default.post(name: .episodeQueueUpdated, object: nil)
            }
            
        } catch {
            LogManager.shared.error("Error updating episode queue position: \(error)")
            context.rollback()
        }
    }
}

// MARK: - Missing Helper Functions
extension Float {
    func nonZeroOrDefault(_ defaultValue: Float) -> Float {
        return self == 0 ? defaultValue : self
    }
}

extension Notification.Name {
    static let episodeQueueUpdated = Notification.Name("episodeQueueUpdated")
    static let episodePlaybackStateChanged = Notification.Name("episodePlaybackStateChanged")
}
