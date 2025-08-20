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
            // Only update now playing info after audio actually starts playing
            // This eliminates the 6ms delay during episode loading
            if playbackState != oldValue && playbackState.isPlaying {
                Task.detached(priority: .userInitiated) {
                    await self.updateNowPlayingInfoAsync()
                }
            }
        }
    }
    
    // MARK: - State Intents
    private var userInitiatedPause = false
    private var wasInterruptedByRouteChange = false
    private var lastRouteChangeReason: AVAudioSession.RouteChangeReason?
    
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
    private var positionUpdateWorkItem: DispatchWorkItem?
    
    @Published var playbackSpeed: Float = UserDefaults.standard.float(forKey: "playbackSpeed").nonZeroOrDefault(1.0) {
        didSet {
            UserDefaults.standard.set(playbackSpeed, forKey: "playbackSpeed")
            player?.rate = isPlaying ? playbackSpeed : 0.0
            Task.detached(priority: .userInitiated) {
                await self.updateNowPlayingInfoAsync()
            }
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
    
    // MARK: - Optimized State Management
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
        LogManager.shared.info("Clearing episode from state: \(playbackState.episode?.title?.prefix(20) ?? "nil") -> nil")
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
        
        LogManager.shared.info("Toggle playback for: \(episode.title?.prefix(30) ?? "Episode")")
        
        // Handle current episode
        if let currentEpisode = playbackState.episode, currentEpisode.id == episodeID {
            if playbackState.isPlaying {
                pause() // This sets userInitiatedPause = true
            } else if playbackState.isLoading {
                LogManager.shared.info("Already loading - ignoring")
            } else {
                // User explicitly wants to resume
                userInitiatedPause = false
                wasInterruptedByRouteChange = false
                resume()
            }
            return
        }
        
        // Start new episode (user explicit action)
        userInitiatedPause = false
        wasInterruptedByRouteChange = false
        startPlayback(for: episode)
    }
    
    private func shouldAutoResume() -> Bool {
        // Never auto-resume if user explicitly paused
        if userInitiatedPause {
            return false
        }
        
        // Only consider auto-resume for system interruptions, not route changes
        if wasInterruptedByRouteChange {
            return false
        }
        
        return false // For now, never auto-resume
    }
    
    // MARK: - Optimized startPlayback (minimal synchronous work)
    private func startPlayback(for episode: Episode) {
        guard let episodeID = episode.id,
              let audioURL = episode.audio,
              !audioURL.isEmpty,
              let url = URL(string: audioURL) else {
            LogManager.shared.error("Invalid episode data")
            return
        }
        
        // Minimal synchronous Core Data reads
        let savedPosition = episode.playbackPosition
        let duration = episode.actualDuration > 0 ? episode.actualDuration : episode.duration
        
        // Update state immediately with loading status (no now playing update triggered)
        updateState(episode: episode, position: savedPosition, duration: duration, isPlaying: false, isLoading: true)
        
        // Move all heavy work to background task
        Task.detached(priority: .userInitiated) {
            await self.setupPlayerOptimized(url: url, episode: episode, startPosition: savedPosition)
        }
    }
    
    // MARK: - Optimized setupPlayer (streamlined async setup)
    private func setupPlayerOptimized(url: URL, episode: Episode, startPosition: Double) async {
        guard let episodeID = episode.id else { return }
        
        // Handle previous episode cleanup
        let previousEpisode = await MainActor.run { self.playbackState.episode }
        if let previousEpisode = previousEpisode, previousEpisode.id != episodeID {
            await saveCurrentPosition()
            await MainActor.run {
                previousEpisode.nowPlaying = false
                try? previousEpisode.managedObjectContext?.save()
            }
        }
        
        await MainActor.run {
            // Clean up and create new player
            self.cleanupPlayer()
            self.cachedArtwork = nil
            
            let playerItem = AVPlayerItem(url: url)
            self.player = AVPlayer(playerItem: playerItem)
            
            self.setupPlayerObservations(for: episodeID)
            self.configureAudioSession()
            self.moveEpisodeToFrontOfQueue(episode)
        }
        
        // Wait for ready state
        await waitForPlayerReady()
        
        // Seek if needed
        if startPosition > 0 {
            await seekToPosition(startPosition)
        }
        
        // Start playback - this will trigger now playing update via didSet
        await MainActor.run {
            self.player?.playImmediately(atRate: self.playbackSpeed)
            
            episode.nowPlaying = true
            if episode.isPlayed {
                removeEpisodeFromPlaylist(episode, playlistName: "Played")
            }
            try? episode.managedObjectContext?.save()
        }
    }
    
    // MARK: - Optimized pause (immediate position save)
    private func pause() {
        guard let player = player else { return }
        
        userInitiatedPause = true
        player.pause()
        
        // Update state immediately
        updateState(isPlaying: false, isLoading: false)
        
        // Save position asynchronously to avoid blocking
        if let episode = playbackState.episode {
            let currentPosition = playbackState.position
            
            // Update in-memory immediately
            episode.playbackPosition = currentPosition
            
            // Save to disk asynchronously
            let objectID = episode.objectID
            Task.detached(priority: .background) {
                let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
                backgroundContext.perform {
                    do {
                        if let episodeInBackground = try backgroundContext.existingObject(with: objectID) as? Episode {
                            episodeInBackground.playbackPosition = currentPosition
                            if backgroundContext.hasChanges {
                                try backgroundContext.save()
                            }
                        }
                    } catch {
                        LogManager.shared.error("Failed to save position: \(error)")
                    }
                }
            }
            
            LogManager.shared.info("Saved position immediately: \(String(format: "%.1f", currentPosition))")
        }
    }
    
    private func resume() {
        guard let player = player else {
            LogManager.shared.warning("No player available - user must explicitly restart")
            return
        }
        
        // Check if player item is still valid
        if let currentItem = player.currentItem, currentItem.status == .readyToPlay {
            // Reset user pause flag when user explicitly resumes
            userInitiatedPause = false
            wasInterruptedByRouteChange = false
            
            // Ensure audio session is properly configured before resuming
            configureAudioSession()
            
            player.playImmediately(atRate: playbackSpeed)
            updateState(isPlaying: true, isLoading: false)
        } else {
            // Player item is invalid, but don't auto-restart
            LogManager.shared.warning("Player item invalid - user must restart manually")
            if let episode = playbackState.episode {
                // Just clear the state, don't restart
                updateState(isPlaying: false, isLoading: false)
            }
        }
    }
    
    func stop() {
        // Save final position
        if let episode = playbackState.episode {
            let currentPosition = playbackState.position
            episode.playbackPosition = currentPosition
            
            // Async save
            let objectID = episode.objectID
            Task.detached(priority: .background) {
                let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
                backgroundContext.perform {
                    do {
                        if let episodeInBackground = try backgroundContext.existingObject(with: objectID) as? Episode {
                            episodeInBackground.playbackPosition = currentPosition
                            episodeInBackground.nowPlaying = false
                            if backgroundContext.hasChanges {
                                try backgroundContext.save()
                            }
                        }
                    } catch {
                        LogManager.shared.error("Failed to save final position: \(error)")
                    }
                }
            }
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
        
        // Rate observer with enhanced logic
        let rateObserver = player.observe(\.rate, options: [.new, .old]) { [weak self] _, change in
            guard let self = self else { return }
            
            let newRate = change.newValue ?? 0
            let oldRate = change.oldValue ?? 0
            
            DispatchQueue.main.async {
                // Only update if this is still the current episode
                guard self.playbackState.episodeID == episodeID else { return }
                
                if newRate > 0 && oldRate == 0 {
                    // Started playing
                    LogManager.shared.info("Audio started playing")
                    self.updateState(isPlaying: true, isLoading: false)
                    
                    // Verify we can actually hear audio
                    self.verifyAudioOutput()
                    
                } else if newRate == 0 && oldRate > 0 {
                    // Paused (could be system or user)
                    LogManager.shared.info("Audio paused")
                    self.updateState(isPlaying: false, isLoading: false)
                }
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
                    case .failed:
                        LogManager.shared.error("Player item failed: \(item.error?.localizedDescription ?? "unknown")")
                        self.handlePlayerError()
                    case .readyToPlay:
                        LogManager.shared.info("Player ready")
                        // Update duration if needed
                        let duration = item.asset.duration.seconds
                        if duration.isFinite && duration > 0 {
                            self.updateState(duration: duration)
                            
                            // Update episode's actual duration
                            if let episode = self.playbackState.episode, episode.actualDuration <= 0 {
                                episode.actualDuration = duration
                                try? episode.managedObjectContext?.save()
                                LogManager.shared.info("Updated actual duration: \(duration)")
                            }
                        }
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
    
    private func verifyAudioOutput() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        
        if route.outputs.isEmpty {
            LogManager.shared.warning("No audio output route available")
            player?.pause()
            updateState(isPlaying: false, isLoading: false)
        } else {
            let outputs = route.outputs.map { $0.portType.rawValue }
            LogManager.shared.info("Audio output verified: \(outputs)")
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
        
        let currentPosition = playbackState.position
        let objectID = episode.objectID
        
        await MainActor.run {
            episode.playbackPosition = currentPosition
        }
        
        Task.detached(priority: .background) {
            let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
            backgroundContext.perform {
                do {
                    if let episodeInBackground = try backgroundContext.existingObject(with: objectID) as? Episode {
                        episodeInBackground.playbackPosition = currentPosition
                        if backgroundContext.hasChanges {
                            try backgroundContext.save()
                        }
                    }
                } catch {
                    LogManager.shared.error("Failed to save current position: \(error)")
                }
            }
        }
    }
    
    // MARK: - Optimized Now Playing Info (moved to async + cached properties)
    private func updateNowPlayingInfoAsync() async {
        guard let episode = playbackState.episode else {
            await MainActor.run {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            }
            return
        }
        
        // Cache expensive Core Data property reads off main thread
        let title = episode.title ?? "Episode"
        let artistName = episode.podcast?.title ?? "Podcast"
        let currentState = playbackState
        
        // Build basic info dictionary without artwork first
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artistName,
            MPNowPlayingInfoPropertyPlaybackRate: currentState.isPlaying ? playbackSpeed : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentState.position,
            MPMediaItemPropertyPlaybackDuration: currentState.duration,
            MPNowPlayingInfoPropertyMediaType: 1
        ]
        
        // Set basic info immediately
        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
        
        // Handle artwork separately to avoid blocking initial setup
        if currentState.isPlaying {
            await updateArtworkAsync(for: episode, baseInfo: nowPlayingInfo)
        }
    }
    
    // MARK: - Async Artwork Loading (prevents blocking episode start)
    private func updateArtworkAsync(for episode: Episode, baseInfo: [String: Any]) async {
        if let cachedArtwork = cachedArtwork {
            var updatedInfo = baseInfo
            updatedInfo[MPMediaItemPropertyArtwork] = cachedArtwork
            
            await MainActor.run {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
            }
            return
        }
        
        // Fetch artwork asynchronously
        let imageUrls = [episode.episodeImage, episode.podcast?.image]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        
        guard let validImageUrl = imageUrls.first, let url = URL(string: validImageUrl) else {
            return
        }
        
        // Check cache first
        let cacheResult = await withCheckedContinuation { continuation in
            KingfisherManager.shared.cache.retrieveImage(forKey: url.cacheKey) { result in
                continuation.resume(returning: result)
            }
        }
        
        switch cacheResult {
        case .success(let value):
            if let cachedImage = value.image {
                let artwork = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in cachedImage }
                await updateNowPlayingWithArtwork(artwork: artwork, baseInfo: baseInfo)
            } else {
                await downloadArtworkAsync(from: url, baseInfo: baseInfo)
            }
        case .failure:
            await downloadArtworkAsync(from: url, baseInfo: baseInfo)
        }
    }
    
    // MARK: - Async Artwork Download
    private func downloadArtworkAsync(from url: URL, baseInfo: [String: Any]) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            
            // Cache the image
            try await KingfisherManager.shared.cache.store(image, forKey: url.cacheKey)
            
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await updateNowPlayingWithArtwork(artwork: artwork, baseInfo: baseInfo)
            
        } catch {
            LogManager.shared.warning("Failed to download artwork: \(error)")
        }
    }
    
    // MARK: - Helper for artwork updates
    private func updateNowPlayingWithArtwork(artwork: MPMediaItemArtwork, baseInfo: [String: Any]) async {
        await MainActor.run {
            var updatedInfo = baseInfo
            updatedInfo[MPMediaItemPropertyArtwork] = artwork
            self.cachedArtwork = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
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
        
        LogManager.shared.info("Episode finished: \(episode.title?.prefix(30) ?? "Episode")")
        
        let context = episode.managedObjectContext ?? viewContext
        let wasPlayed = episode.isPlayed
        
        // DEBUG: Check episode queue status before removal
        LogManager.shared.info("Episode queue status before completion: isQueued=\(episode.isQueued), position=\(episode.queuePosition)")
        
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
            
            // DEBUG: Check queue before removal
            let queueBefore = fetchQueuedEpisodes()
            LogManager.shared.info("Queue before removal: \(queueBefore.count) episodes")
            for (index, ep) in queueBefore.enumerated() {
                LogManager.shared.info("   \(index): \(ep.title?.prefix(20) ?? "No title") - \(ep.id?.prefix(8) ?? "no-id")")
            }
            
            Task { @MainActor in
                removeFromQueue(episode)
            }
            
            // DEBUG: Check queue after removal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let queueAfter = fetchQueuedEpisodes()
                LogManager.shared.info("Queue after removal: \(queueAfter.count) episodes")
                for (index, ep) in queueAfter.enumerated() {
                    LogManager.shared.info("   \(index): \(ep.title?.prefix(20) ?? "No title") - \(ep.id?.prefix(8) ?? "no-id")")
                }
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
            let queuedEpisodes = fetchQueuedEpisodes()
            if let nextEpisode = queuedEpisodes.first {
                LogManager.shared.info("Auto-playing next episode: \(nextEpisode.title?.prefix(30) ?? "Next")")
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
            LogManager.shared.info("Attempting error recovery at position \(savedPosition)")
            
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
        
        // Check if this is the current episode (regardless of play/pause state)
        let isCurrentEpisode = (playbackState.episode?.id == episode.id)
        let progressBeforeStop = isCurrentEpisode ? playbackState.position : episode.playbackPosition
        
        let wasPlayed = episode.isPlayed // Store original state
        
        if episode.isPlayed {
            // Unmark as played
            episode.isPlayed = false
        } else {
            // Mark as played
            episode.isPlayed = true
            
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
        
        // CRITICAL: Stop playback if this is the current episode (playing OR paused)
        if isCurrentEpisode {
            // Cancel any pending position saves
            positionSaveTimer?.invalidate()
            positionSaveTimer = nil
            
            // Clear state immediately without saving current position
            LogManager.shared.info("Stopping player for manual mark as played")
            clearState()
            cleanupPlayer()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        
        // Remove from queue if episode was just marked as played (not unmarked)
        if !wasPlayed && episode.isPlayed {
            LogManager.shared.info("Removing manually marked episode from queue")
            
            Task { @MainActor in
                removeFromQueue(episode)
            }
            
            // Check if we need to clear player state after queue removal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.checkQueueStatusAfterRemoval()
            }
        }
        
        do {
            try context.save()
            LogManager.shared.info("Manual mark as played completed")
        } catch {
            LogManager.shared.error("Failed to save manual mark as played: \(error)")
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
    
    // MARK: - Audio Session & Setup
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Try to set category first
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .defaultToSpeaker])
            
            // Verify the route before activating
            let currentRoute = session.currentRoute
            LogManager.shared.info("Current audio route: \(currentRoute.outputs.map { $0.portType.rawValue })")
            
            // Activate session
            try session.setActive(true)
            
            LogManager.shared.info("Audio session configured successfully")
            
        } catch {
            LogManager.shared.error("Failed to configure audio session: \(error)")
            
            // If we can't configure audio session, don't proceed with playback
            if playbackState.isPlaying {
                updateState(isPlaying: false, isLoading: false)
            }
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
            LogManager.shared.info("Audio interruption began")
            wasInterruptedByRouteChange = false // This is a different type of interruption
            userInitiatedPause = false
            
            // Save position asynchronously
            if let episode = playbackState.episode {
                let currentPosition = playbackState.position
                episode.playbackPosition = currentPosition
                
                let objectID = episode.objectID
                Task.detached(priority: .background) {
                    let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
                    backgroundContext.perform {
                        do {
                            if let episodeInBackground = try backgroundContext.existingObject(with: objectID) as? Episode {
                                episodeInBackground.playbackPosition = currentPosition
                                if backgroundContext.hasChanges {
                                    try backgroundContext.save()
                                }
                            }
                        } catch {
                            LogManager.shared.error("Failed to save position during interruption: \(error)")
                        }
                    }
                }
            }
            
        case .ended:
            LogManager.shared.info("Audio interruption ended")
            
            // Check if we should resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && !userInitiatedPause {
                    LogManager.shared.info("System suggests resume, but letting user decide")
                    // Still don't auto-resume - respect user preference
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        lastRouteChangeReason = reason
        
        switch reason {
        case .oldDeviceUnavailable:
            LogManager.shared.info("Audio device disconnected")
            wasInterruptedByRouteChange = true
            userInitiatedPause = false // This wasn't user-initiated
            
            // Save position asynchronously
            if let episode = playbackState.episode {
                let currentPosition = playbackState.position
                episode.playbackPosition = currentPosition
                
                let objectID = episode.objectID
                Task.detached(priority: .background) {
                    let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
                    backgroundContext.perform {
                        do {
                            if let episodeInBackground = try backgroundContext.existingObject(with: objectID) as? Episode {
                                episodeInBackground.playbackPosition = currentPosition
                                if backgroundContext.hasChanges {
                                    try backgroundContext.save()
                                }
                            }
                        } catch {
                            LogManager.shared.error("Failed to save position during route change: \(error)")
                        }
                    }
                }
            }
            
        case .newDeviceAvailable:
            LogManager.shared.info("Audio device connected")
            // Don't auto-resume - let user decide
            
        default:
            LogManager.shared.info("Audio route changed: \(reason)")
            break
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Save current state asynchronously
        if let episode = playbackState.episode {
            let currentPosition = playbackState.position
            episode.playbackPosition = currentPosition
            
            let objectID = episode.objectID
            Task.detached(priority: .background) {
                let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
                backgroundContext.perform {
                    do {
                        if let episodeInBackground = try backgroundContext.existingObject(with: objectID) as? Episode {
                            episodeInBackground.playbackPosition = currentPosition
                            if backgroundContext.hasChanges {
                                try backgroundContext.save()
                            }
                        }
                    } catch {
                        LogManager.shared.error("Failed to save position on background: \(error)")
                    }
                }
            }
        }
        
        LogManager.shared.info("App backgrounded - was playing: \(playbackState.isPlaying)")
    }

    @objc private func appWillEnterForeground() {
        LogManager.shared.info("App foregrounding")
        
        // Only log the state for debugging
        if let episode = playbackState.episode {
            LogManager.shared.info("Current episode: \(episode.title?.prefix(30) ?? "Unknown")")
            LogManager.shared.info("Was interrupted by route change: \(wasInterruptedByRouteChange)")
            LogManager.shared.info("User initiated pause: \(userInitiatedPause)")
            LogManager.shared.info("Last route change: \(lastRouteChangeReason?.rawValue ?? 0)")
        }
    }
    
    @objc private func savePlaybackOnExit() {
        if let episode = playbackState.episode {
            let currentPosition = playbackState.position
            episode.playbackPosition = currentPosition
            try? episode.managedObjectContext?.save()
        }
    }
    
    // MARK: - Remote Controls & Legacy Artwork Methods
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
                    self.wasInterruptedByRouteChange = false
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
    
    // Legacy sync artwork method (kept for compatibility, but calls async version)
    private func fetchArtwork(for episode: Episode, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        Task.detached(priority: .userInitiated) {
            if let cachedArtwork = await MainActor.run(body: { self.cachedArtwork }) {
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
            
            let cacheResult = await withCheckedContinuation { continuation in
                KingfisherManager.shared.cache.retrieveImage(forKey: url.cacheKey) { result in
                    continuation.resume(returning: result)
                }
            }
            
            switch cacheResult {
            case .success(let value):
                if let cachedImage = value.image {
                    let artwork = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in cachedImage }
                    await MainActor.run {
                        self.cachedArtwork = artwork
                    }
                    completion(artwork)
                } else {
                    await self.downloadAndCacheArtwork(from: url, completion: completion)
                }
            case .failure:
                await self.downloadAndCacheArtwork(from: url, completion: completion)
            }
        }
    }
    
    private func downloadAndCacheArtwork(from url: URL, completion: @escaping (MPMediaItemArtwork?) -> Void) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                completion(nil)
                return
            }
            
            KingfisherManager.shared.cache.store(image, forKey: url.cacheKey) { _ in }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            
            await MainActor.run {
                self.cachedArtwork = artwork
            }
            
            completion(artwork)
        } catch {
            completion(nil)
        }
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
        
        // Immediate UI feedback
        episode.objectWillChange.send()
        
        // Ensure episode is queued
        if !episode.isQueued {
            LogManager.shared.info("Adding episode to queue: \(episode.title?.prefix(30) ?? "Episode")")
            episode.isQueued = true
        }
        
        // Get current queue order
        let queue = getQueuedEpisodes(context: context)
        
        if queue.first?.id == episode.id {
            // Already at front, just save to ensure consistency
            try? context.save()
            return
        }
        
        // Move to front: remove from current position and insert at 0
        var reordered = queue.filter { $0.id != episode.id }
        reordered.insert(episode, at: 0)
        
        // Update all positions with immediate UI feedback
        for (index, ep) in reordered.enumerated() {
            ep.objectWillChange.send()
            ep.queuePosition = Int64(index)
        }
        
        do {
            try context.save()
            LogManager.shared.info("Moved episode to front of queue: \(episode.title?.prefix(30) ?? "Episode")")
            
            Task { @MainActor in
                // Try to find EpisodesViewModel and update it
                NotificationCenter.default.post(name: .episodeQueueUpdated, object: nil)
            }
            
        } catch {
            LogManager.shared.error("Failed to move episode to front: \(error)")
            context.rollback()
        }
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
            
            // Notify views
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

    /// Optimized queue reordering for drag/drop operations
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
            
            // Notify views
            NotificationCenter.default.post(name: .episodeQueueUpdated, object: nil)
            
        } catch {
            LogManager.shared.error("Error reordering queue: \(error)")
            context.rollback()
        }
    }

    /// Helper function to update queue position for episode with immediate UI feedback
    func updateEpisodeQueuePosition(_ episode: Episode, to position: Int) {
        guard let context = episode.managedObjectContext else { return }
        
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Immediate UI feedback
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
            
            // Notify views of queue change
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
