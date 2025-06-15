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
    let queuePlaylist = getQueuePlaylist(context: context)
    
    guard let items = queuePlaylist.items as? Set<Episode> else {
        return []
    }
    
    return items.sorted { $0.queuePosition < $1.queuePosition }
}

class AudioPlayerManager: ObservableObject, @unchecked Sendable {
    static let shared = AudioPlayerManager()
    
    // MARK: - Single Source of Truth
    @Published private(set) var playbackState = PlaybackState.idle {
        didSet {
            if playbackState != oldValue {
                updateDerivedState()
                updateNowPlayingInfo()
                savePositionIfNeeded()
                
//                LogManager.shared.info("🎯 State: episode=\(playbackState.episode?.title?.prefix(20) ?? "nil"), pos=\(String(format: "%.1f", playbackState.position)), playing=\(playbackState.isPlaying), loading=\(playbackState.isLoading)")
            }
        }
    }
    
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
    private var wasPlayingBeforeBackground = false
    private var cachedArtwork: MPMediaItemArtwork?
    
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
        }
    }
    
    @Published var backwardInterval: Double = UserDefaults.standard.double(forKey: "backwardInterval") != 0 ? UserDefaults.standard.double(forKey: "backwardInterval") : 15 {
        didSet {
            UserDefaults.standard.set(backwardInterval, forKey: "backwardInterval")
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
        setupNotifications()
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
    }
    
    private func clearState() {
        LogManager.shared.info("🔄 Clearing episode from state: \(playbackState.episode?.title?.prefix(20) ?? "nil") -> nil")
        playbackState = PlaybackState.idle
    }
    
    private func updateDerivedState() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Core Playback Control
    func togglePlayback(for episode: Episode) {
        guard let episodeID = episode.id else { return }
        
        LogManager.shared.info("🎮 Toggle playback for: \(episode.title?.prefix(30) ?? "Episode")")
        
        // Handle current episode
        if let currentEpisode = playbackState.episode, currentEpisode.id == episodeID {
            if playbackState.isPlaying {
                pause()
            } else if playbackState.isLoading {
                LogManager.shared.info("⏳ Already loading - ignoring")
            } else {
                resume()
            }
            return
        }
        
        // Start new episode
        startPlayback(for: episode)
    }
    
    private func startPlayback(for episode: Episode) {
        guard let episodeID = episode.id,
              let audioURL = episode.audio,
              !audioURL.isEmpty,
              let url = URL(string: audioURL) else {
            LogManager.shared.error("❌ Invalid episode data")
            return
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
        
        // Handle previous episode
        let previousEpisode = await MainActor.run { self.playbackState.episode }
        if let previousEpisode = previousEpisode, previousEpisode.id != episodeID {
            await saveCurrentPosition()
            await MainActor.run {
                previousEpisode.nowPlaying = false
                try? previousEpisode.managedObjectContext?.save()
            }
        }
        
        await MainActor.run {
            // Clean up previous player
            self.cleanupPlayer()
            self.cachedArtwork = nil
            
            // Create new player
            let playerItem = AVPlayerItem(url: url)
            self.player = AVPlayer(playerItem: playerItem)
            
            // Set up observations
            self.setupPlayerObservations(for: episodeID)
            self.configureAudioSession()
            
            // Move to front of queue
            self.moveEpisodeToFrontOfQueue(episode)
        }
        
        // Wait for player to be ready
        await waitForPlayerReady()
        
        // Seek to saved position if needed
        if startPosition > 0 {
            await seekToPosition(startPosition)
        }
        
        // Start playback
        await MainActor.run {
            self.player?.playImmediately(atRate: self.playbackSpeed)
            
            // Update episode state
            episode.nowPlaying = true
            if episode.isPlayed {
                episode.isPlayed = false
                episode.playedDate = nil
            }
            try? episode.managedObjectContext?.save()
            
            // Defer metadata update slightly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.updateNowPlayingInfo()
            }
        }
    }
    
    private func pause() {
        guard let player = player else { return }
        
        player.pause()
        updateState(isPlaying: false, isLoading: false)
        
        // Save position immediately on pause
        if let episode = playbackState.episode {
            savePositionImmediately(for: episode, position: playbackState.position)
        }
    }
    
    private func resume() {
        guard let player = player else {
            // If no player, restart playback
            if let episode = playbackState.episode {
                startPlayback(for: episode)
            }
            return
        }
        
        // Check if player item is still valid
        if let currentItem = player.currentItem, currentItem.status == .readyToPlay {
            player.playImmediately(atRate: playbackSpeed)
            updateState(isPlaying: true, isLoading: false)
        } else {
            // Player item is invalid, restart
            if let episode = playbackState.episode {
                LogManager.shared.warning("⚠️ Player item invalid - restarting playback")
                startPlayback(for: episode)
            }
        }
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
        
        LogManager.shared.info("🛑 Player stopped and state cleared")
    }
    
    // MARK: - Player Observations
    private func setupPlayerObservations(for episodeID: String) {
        guard let player = player else { return }
        
        // Clean up previous observations
        playerObservations.forEach { $0.invalidate() }
        playerObservations.removeAll()
        
        // Rate observer (for play/pause state)
        let rateObserver = player.observe(\.rate, options: [.new, .old]) { [weak self] _, change in
            guard let self = self else { return }
            
            let newRate = change.newValue ?? 0
            let oldRate = change.oldValue ?? 0
            
            DispatchQueue.main.async {
                // Only update if this is still the current episode
                guard self.playbackState.episodeID == episodeID else { return }
                
                if newRate > 0 && oldRate == 0 {
                    // Started playing
                    LogManager.shared.info("🎵 Audio started playing")
                    self.updateState(isPlaying: true, isLoading: false)
                } else if newRate == 0 && oldRate > 0 {
                    // Paused
                    LogManager.shared.info("⏸️ Audio paused")
                    self.updateState(isPlaying: false, isLoading: false)
                }
            }
        }
        playerObservations.append(rateObserver)
        
        // Time observer (for position updates) - FIXED
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 10),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            
            // Only update if this is still the current episode
            guard self.playbackState.episodeID == episodeID,
                  !self.isSeekingManually else { return }
            
            let newPosition = time.seconds
            guard newPosition.isFinite && newPosition >= 0 else { return }
            
            // Check if player actually stopped (rate = 0) but we're still near the end
            let playerRate = self.player?.rate ?? 0
            let duration = self.playbackState.duration
            let isNearEnd = duration > 0 && newPosition >= (duration - 3.0) // 3 second buffer
            let hasValidDuration = duration > 10 // At least 10 seconds long
            
            // CRITICAL: Detect if player stopped playing near the end (background completion)
            if isNearEnd && hasValidDuration && playerRate == 0 && self.playbackState.isPlaying {
                LogManager.shared.info("🏁 Background episode completion detected: pos=\(newPosition), duration=\(duration), rate=\(playerRate)")
                self.handleEpisodeEnd()
                return
            }
            
            // Normal end detection for foreground
            if isNearEnd && hasValidDuration && playerRate > 0 {
                LogManager.shared.info("🏁 Foreground episode ending detected: pos=\(newPosition), duration=\(duration)")
                self.handleEpisodeEnd()
                return
            }
            
            // Update position
            self.updateState(position: newPosition)
        }
        
        // Status observer (for errors/ready state)
        if let currentItem = player.currentItem {
            let statusObserver = currentItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    guard self.playbackState.episodeID == episodeID else { return }
                    
                    switch item.status {
                    case .failed:
                        LogManager.shared.error("❌ Player item failed: \(item.error?.localizedDescription ?? "unknown")")
                        self.handlePlayerError()
                    case .readyToPlay:
                        LogManager.shared.info("✅ Player ready")
                        // Update duration if needed
                        let duration = item.asset.duration.seconds
                        if duration.isFinite && duration > 0 {
                            self.updateState(duration: duration)
                            
                            // Update episode's actual duration
                            if let episode = self.playbackState.episode, episode.actualDuration <= 0 {
                                episode.actualDuration = duration
                                try? episode.managedObjectContext?.save()
                                LogManager.shared.info("✅ Updated actual duration: \(duration)")
                            }
                        }
                    default:
                        break
                    }
                }
            }
            playerObservations.append(statusObserver)
            
            // ADD: Player item ended notification observer
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: currentItem,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                guard self.playbackState.episodeID == episodeID else { return }
                
                LogManager.shared.info("🏁 AVPlayerItemDidPlayToEndTime notification received")
                // Small delay to ensure any final time updates are processed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.handleEpisodeEnd()
                }
            }
            
            // ADD: Player stalled notification (backup detection)
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
                    LogManager.shared.info("🏁 Player stalled near end - checking for completion: pos=\(currentTime), duration=\(duration)")
                    
                    // Wait a moment and check if we're actually at the end
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let finalTime = self.player?.currentTime().seconds ?? 0
                        if finalTime >= (duration - 5.0) {
                            LogManager.shared.info("🏁 Confirmed episode completion via stall detection")
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
        LogManager.shared.info("💾 Saved position immediately: \(String(format: "%.1f", position))")
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
                            LogManager.shared.info("💾 Background saved position: \(String(format: "%.1f", position))")
                        }
                    }
                } catch {
                    LogManager.shared.error("❌ Failed to save position: \(error)")
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
                    LogManager.shared.warning("⚠️ Seek failed")
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
    
    private func waitForPlayerReady() async {
        guard let player = player, let currentItem = player.currentItem else { return }
        
        while currentItem.status == .unknown {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
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
        
        LogManager.shared.info("🏁 Episode finished: \(episode.title?.prefix(30) ?? "Episode")")
        
        let context = episode.managedObjectContext ?? viewContext
        let wasPlayed = episode.isPlayed
        
        // DEBUG: Check episode queue status before removal
        LogManager.shared.info("🔍 Episode queue status before completion: isQueued=\(episode.isQueued), position=\(episode.queuePosition)")
        
        // CRITICAL: Cancel any pending position saves FIRST and reset position immediately
        positionSaveTimer?.invalidate()
        positionSaveTimer = nil
        
        // CRITICAL: Reset position to 0 BEFORE any other operations
        episode.playbackPosition = 0
        
        // Mark as played (same pattern as markAsPlayed)
        episode.isPlayed = true
        episode.nowPlaying = false
        episode.playedDate = Date()
        episode.addPlayedDate(Date.now)
        
        if let podcast = episode.podcast {
            podcast.playCount += 1
            podcast.playedSeconds += playbackState.duration
        }
        
        // Remove from queue in same transaction
        if !wasPlayed {
            LogManager.shared.info("🗑️ Removing finished episode from queue")
            
            // DEBUG: Check queue before removal
            let queueBefore = fetchQueuedEpisodes()
            LogManager.shared.info("📊 Queue before removal: \(queueBefore.count) episodes")
            for (index, ep) in queueBefore.enumerated() {
                LogManager.shared.info("   \(index): \(ep.title?.prefix(20) ?? "No title") - \(ep.id?.prefix(8) ?? "no-id")")
            }
            
            removeFromQueue(episode)
            
            // DEBUG: Check queue after removal
            let queueAfter = fetchQueuedEpisodes()
            LogManager.shared.info("📊 Queue after removal: \(queueAfter.count) episodes")
            for (index, ep) in queueAfter.enumerated() {
                LogManager.shared.info("   \(index): \(ep.title?.prefix(20) ?? "No title") - \(ep.id?.prefix(8) ?? "no-id")")
            }
        } else {
            LogManager.shared.info("⏭️ Episode was already played - not removing from queue")
        }
        
        // Single save for all changes
        do {
            try context.save()
            LogManager.shared.info("✅ Episode marked as played and saved with position reset to 0")
        } catch {
            LogManager.shared.error("❌ Failed to save episode completion: \(error)")
        }
        
        // Clear player state AFTER saving (only if not already cleared by removeFromQueue)
        if playbackState.episode != nil {
            LogManager.shared.info("🔄 Clearing player state after episode completion")
            clearState()
            cleanupPlayer()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        } else {
            LogManager.shared.info("🔄 Player state already cleared by queue removal")
        }
        
        // Check for autoplay AFTER clearing state
        if autoplayNext {
            let queuedEpisodes = fetchQueuedEpisodes()
            if let nextEpisode = queuedEpisodes.first {
                LogManager.shared.info("🔄 Auto-playing next episode: \(nextEpisode.title?.prefix(30) ?? "Next")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startPlayback(for: nextEpisode)
                }
                return
            }
        }
        
        // Final queue status check
        checkQueueStatusAfterRemoval()
    }
    
    private func handlePlayerError() {
        // Try to recover once
        if let episode = playbackState.episode {
            let savedPosition = episode.playbackPosition
            LogManager.shared.info("🔄 Attempting error recovery at position \(savedPosition)")
            
            // Reset state and try again
            updateState(position: savedPosition, isPlaying: false, isLoading: true)
            
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                await MainActor.run {
                    self.startPlayback(for: episode)
                }
            }
        }
    }
    
    private func cleanupPlayer() {
        timeObserver.map { player?.removeTimeObserver($0) }
        timeObserver = nil
        
        playerObservations.forEach { $0.invalidate() }
        playerObservations.removeAll()
        
        player?.pause()
        player?.replaceCurrentItem(with: nil)
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
        
        let isCurrentlyPlaying = (playbackState.episode?.id == episode.id) && isPlaying
        let progressBeforeStop = isCurrentlyPlaying ? playbackState.position : episode.playbackPosition
        
        let wasPlayed = episode.isPlayed // Store original state
        
        if episode.isPlayed {
            episode.isPlayed = false
            episode.playedDate = nil
        } else {
            episode.isPlayed = true
            episode.playedDate = Date.now
            episode.addPlayedDate(Date.now)
            
            let actualDuration = getActualDuration(for: episode)
            let playedTime = manually ? progressBeforeStop : actualDuration
            
            if let podcast = episode.podcast {
                podcast.playCount += 1
                podcast.playedSeconds += playedTime
            }
        }
        
        // CRITICAL: Reset episode position and nowPlaying FIRST
        episode.playbackPosition = 0
        episode.nowPlaying = false
        
        // CRITICAL: Stop playback BEFORE queue operations to prevent position save
        if isCurrentlyPlaying {
            // Cancel any pending position saves
            positionSaveTimer?.invalidate()
            positionSaveTimer = nil
            
            // Clear state immediately without saving current position
            LogManager.shared.info("🛑 Stopping player for manual mark as played")
            clearState()
            cleanupPlayer()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        
        // Remove from queue if episode was just marked as played (not unmarked)
        if !wasPlayed && episode.isPlayed {
            LogManager.shared.info("🗑️ Removing manually marked episode from queue")
            removeFromQueue(episode)
            
            // Check if we need to clear player state after queue removal
            checkQueueStatusAfterRemoval()
        }
        
        do {
            try context.save()
            LogManager.shared.info("✅ Manual mark as played completed")
        } catch {
            LogManager.shared.error("❌ Failed to save manual mark as played: \(error)")
        }
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
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
                LogManager.shared.warning("⚠️ Failed to load actual duration: \(error)")
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
        
        let playingOrResumed = isPlayingEpisode(episode) || hasStartedPlayback(for: episode)
        
        let valueToShow: Double
        if playingOrResumed && progress > 0 {
            valueToShow = max(0, duration - progress)
        } else {
            valueToShow = duration
        }
        
        let seconds = Int(valueToShow)
        return pretty ? formatDuration(seconds: seconds) : formatView(seconds: seconds)
    }
    
    // MARK: - Audio Session & Setup
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            LogManager.shared.error("❌ Failed to configure audio session: \(error)")
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(savePlaybackOnExit), name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            LogManager.shared.info("🔇 Audio interruption began")
            // Just save position - let AVPlayer handle the pause automatically
            if let episode = playbackState.episode {
                savePositionImmediately(for: episode, position: playbackState.position)
            }
            
        case .ended:
            LogManager.shared.info("🔊 Audio interruption ended")
            // Don't auto-resume anything - let the user decide
            // The system/user will resume if they want to
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        switch reason {
        case .oldDeviceUnavailable:
            LogManager.shared.info("🔌 Audio device disconnected")
            // Save position but let the system handle pausing
            if let episode = playbackState.episode {
                savePositionImmediately(for: episode, position: playbackState.position)
            }
            
        case .newDeviceAvailable:
            LogManager.shared.info("🔌 Audio device connected")
            // Just log - no auto-resume behavior
            
        default:
            LogManager.shared.info("🔄 Audio route changed: \(reason)")
            break
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Don't pause automatically - let the system handle it
        // Just save the current state
        if let episode = playbackState.episode {
            savePositionImmediately(for: episode, position: playbackState.position)
        }
        
        LogManager.shared.info("📱 App backgrounded - was playing: \(playbackState.isPlaying)")
    }

    @objc private func appWillEnterForeground() {
        LogManager.shared.info("📱 App foregrounding")
        
        // Reset any tracking variables
        wasPlayingBeforeBackground = false
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
            self?.resume()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward(seconds: 30)
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward(seconds: 15)
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
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
    }
    
    func setForwardInterval(_ interval: Double) {
        forwardInterval = interval
    }
    
    func setBackwardInterval(_ interval: Double) {
        backwardInterval = interval
    }
    private func moveEpisodeToFrontOfQueue(_ episode: Episode) {
        guard let context = episode.managedObjectContext else { return }
        
        queueLock.lock()
        defer { queueLock.unlock() }
        
        let queuePlaylist = getQueuePlaylist(context: context)
        
        if !episode.isQueued {
            episode.isQueued = true
            queuePlaylist.addToItems(episode)
        }
        
        guard let items = queuePlaylist.items as? Set<Episode> else { return }
        let queue = items.sorted { $0.queuePosition < $1.queuePosition }
        
        if queue.first?.id == episode.id { return }
        
        var reordered = queue.filter { $0.id != episode.id }
        reordered.insert(episode, at: 0)
        
        for (index, ep) in reordered.enumerated() {
            ep.queuePosition = Int64(index)
        }
        
        try? context.save()
    }
    
    private func checkQueueStatusAfterRemoval() {
        // Check if queue is now empty and current episode should be cleared
        let queuedEpisodes = fetchQueuedEpisodes()
        
        if queuedEpisodes.isEmpty {
            // Queue is empty - check if current episode should be cleared
            if let currentEpisode = playbackState.episode, !currentEpisode.isQueued {
                LogManager.shared.warning("🗑️ Queue empty and current episode not queued - clearing player state")
                stop()
            }
        }
    }
    
    /// Public method for global queue functions to call
    func handleQueueRemoval() {
        checkQueueStatusAfterRemoval()
    }
}

extension Float {
    func nonZeroOrDefault(_ defaultValue: Float) -> Float {
        return self == 0 ? defaultValue : self
    }
}
