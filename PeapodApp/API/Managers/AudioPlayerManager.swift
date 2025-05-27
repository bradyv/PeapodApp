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

// MARK: - AudioPlayerState enum for more precise state tracking
enum AudioPlayerState: Equatable {
    case idle
    case loading(episodeID: String)
    case playing(episodeID: String)
    case paused(episodeID: String)
    
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    
    var currentEpisodeID: String? {
        switch self {
        case .loading(let id), .playing(let id), .paused(let id):
            return id
        case .idle:
            return nil
        }
    }
    
    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
    
    // MARK: - Equatable Implementation
    static func == (lhs: AudioPlayerState, rhs: AudioPlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading(let lhsID), .loading(let rhsID)):
            return lhsID == rhsID
        case (.playing(let lhsID), .playing(let rhsID)):
            return lhsID == rhsID
        case (.paused(let lhsID), .paused(let rhsID)):
            return lhsID == rhsID
        default:
            return false
        }
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
    private let queueLock = NSLock()
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerItemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var wasPlayingBeforeBackground = false
    private var lastKnownPosition: Double = 0
    private var lastSavedPosition: Double = 0
    private let positionSaveThreshold: Double = 5.0 // Only save every 5 seconds
    private var positionSaveTimer: Timer?
    @Published private(set) var state: AudioPlayerState = .idle {
        didSet {
            // Update derived properties when state changes
            self.isPlaying = state.isPlaying
            
            // Update UI immediately when state changes
            objectWillChange.send()
        }
    }
    
    // These become computed properties based on state
    @Published private(set) var isPlaying: Bool = false
    @Published var progress: Double = 0
    @Published var currentEpisode: Episode?
    
    // These remain as regular properties
    @Published var playbackSpeed: Float = UserDefaults.standard.float(forKey: "playbackSpeed").nonZeroOrDefault(1.0)
    @Published var forwardInterval: Double = UserDefaults.standard.double(forKey: "forwardInterval") != 0 ? UserDefaults.standard.double(forKey: "forwardInterval") : 30
    @Published var backwardInterval: Double = UserDefaults.standard.double(forKey: "backwardInterval") != 0 ? UserDefaults.standard.double(forKey: "backwardInterval") : 15
    @Published var isSeekingManually: Bool = false
    @Published var autoplayNext: Bool = UserDefaults.standard.bool(forKey: "autoplayNext") {
        didSet {
            UserDefaults.standard.set(autoplayNext, forKey: "autoplayNext")
        }
    }
    
    private func logPlayerState(context: String) {
        guard let player = player else {
            print("🐛 [\(context)] Player: nil")
            return
        }
        
        let rate = player.rate
        let timeControlStatus = player.timeControlStatus
        let currentItemStatus = player.currentItem?.status
        
        print("🐛 [\(context)] Player rate: \(rate), timeControlStatus: \(timeControlStatus)")
        
        if let error = player.currentItem?.error {
            print("🐛 [\(context)] Player item error: \(error.localizedDescription)")
        }
    }
    
    private func addRateObserver(for episodeID: String) {
        guard let player = player else { return }
        
        let rateObserver = player.observe(\.rate, options: [.new, .old]) { [weak self] player, change in
            guard let self = self else { return }
            
            let newRate = change.newValue ?? 0
            let oldRate = change.oldValue ?? 0
            
            DispatchQueue.main.async {
                // Only transition to playing when rate actually goes from 0 to >0
                if newRate > 0 && oldRate == 0 {
                    switch self.state {
                    case .loading(let id) where id == episodeID:
                        print("🎵 Audio actually started playing for episode: \(episodeID)")
                        self.updateState(to: .playing(episodeID: episodeID))
                        
                    case .paused(let id) where id == episodeID:
                        print("▶️ Audio resumed from paused for episode: \(episodeID)")
                        self.updateState(to: .playing(episodeID: episodeID))
                        
                    default:
                        break
                    }
                }
                // Handle transitions to paused state (rate goes from >0 to 0)
                else if newRate == 0 && oldRate > 0 {
                    if case .playing(let id) = self.state, id == episodeID {
                        print("⏸️ Audio paused for episode: \(episodeID)")
                        self.updateState(to: .paused(episodeID: episodeID))
                    }
                }
            }
        }
        
        self.rateObserver = rateObserver
    }
    
    // Helper function to check if a specific episode is loading
    func isLoadingEpisode(_ episode: Episode) -> Bool {
        guard let id = episode.id else { return false }
        
        if case .loading(let episodeID) = state, episodeID == id {
            return true
        }
        return false
    }
    
    // Helper function to check if a specific episode is playing
    func isPlayingEpisode(_ episode: Episode) -> Bool {
        guard let id = episode.id else { return false }
        
        if case .playing(let episodeID) = state, episodeID == id {
            return true
        }
        return false
    }
    
    // Helper function that checks if an episode has started playback
    func hasStartedPlayback(for episode: Episode) -> Bool {
        return getSavedPlaybackPosition(for: episode) > 0
    }
    
    private init() {
        primePlayer()
        configureRemoteTransportControls()
        setupNotifications()
    }
    
    private func primePlayer() {
        // Pre-warm a player without hijacking audio session
        self.player = AVPlayer()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(savePlaybackOnExit), name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
    }
    
    // MARK: - Core Playback Control
    func togglePlayback(for episode: Episode) {
        print("▶️ togglePlayback called for episode: \(episode.title ?? "Episode")")
        guard let episodeID = episode.id else { return }

        switch state {
        case .playing(let id) where id == episodeID:
            print("⏸ Already playing — pausing.")
            pause()
            return
            
        case .paused(let id) where id == episodeID:
            print("▶️ Resuming paused episode")
            
            // Check if player/item is still valid before resuming
            if let player = player,
               let currentItem = player.currentItem,
               currentItem.status == .readyToPlay {
                player.playImmediately(atRate: playbackSpeed)
            } else {
                print("⚠️ Player item invalid - restarting playback instead of resuming")
                // Fall through to restart playback completely
                self.restartPlayback(for: episode)
            }
            return
            
        case .loading(let id) where id == episodeID:
            print("⏳ Already loading — ignoring.")
            return
            
        default:
            break
        }

        // Start fresh playback
        self.startFreshPlayback(for: episode)
    }

    // Split the playback logic into separate methods for clarity
    private func restartPlayback(for episode: Episode) {
        guard let episodeID = episode.id else { return }
        
        // Clean up any existing player state
        cleanupPlayer()
        
        // Start fresh
        self.state = .loading(episodeID: episodeID)
        self.currentEpisode = episode
        
        Task.detached(priority: .userInitiated) {
            await self.play(episode: episode)
            
            await MainActor.run {
                episode.nowPlaying = true
                if episode.isPlayed {
                    episode.isPlayed = false
                    episode.playedDate = nil
                }
            }
            
            await self.saveEpisodeOnMainThread(episode)
        }
    }

    private func startFreshPlayback(for episode: Episode) {
        guard let episodeID = episode.id else { return }
        
        self.state = .loading(episodeID: episodeID)
        self.currentEpisode = episode

        Task.detached(priority: .userInitiated) {
            await self.play(episode: episode)

            await MainActor.run {
                episode.nowPlaying = true
                if episode.isPlayed {
                    episode.isPlayed = false
                    episode.playedDate = nil
                }
            }

            await self.saveEpisodeOnMainThread(episode)
        }
    }
    
    private func play(episode: Episode) async {
        // Validate inputs first
        guard let audio = episode.audio,
              !audio.isEmpty,
              let url = URL(string: audio),
              let episodeID = episode.id else {
            print("❌ Invalid episode data for playback")
            await MainActor.run {
                self.updateState(to: .idle)
                self.currentEpisode = nil
            }
            return
        }

        print("▶️ Starting playback for: \(episode.title ?? "Episode")")

        // Load player item in background
        let playerItem = await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let item = AVPlayerItem(url: url)
                continuation.resume(returning: item)
            }
        }

        // Move to front of queue in background
        await withCheckedContinuation { continuation in
            Task.detached(priority: .background) {
                self.moveEpisodeToFrontOfQueue(episode)
                continuation.resume()
            }
        }

        // Handle previous episode state
        let previousEpisode = await MainActor.run { self.currentEpisode }
        if let previous = previousEpisode, previous.id != episode.id {
            let previousID = previous.objectID
            let position = await MainActor.run { self.player?.currentTime().seconds ?? 0 }

            Task.detached(priority: .background) {
                if let saved = try? viewContext.existingObject(with: previousID) as? Episode {
                    saved.nowPlaying = false
                    saved.playbackPosition = position
                    try? saved.managedObjectContext?.save()
                }
            }
        }

        let lastPosition = getSavedPlaybackPosition(for: episode)

        // Prep player off-main before assigning
        cleanupPlayer()

        // Configure player and start playback
        await MainActor.run {
            self.cachedArtwork = nil
            self.player?.replaceCurrentItem(with: playerItem)
            self.progress = lastPosition
            self.configureAudioSession(activePlayback: true)
            self.setupPlayerItemObservations(playerItem, for: episodeID)
            self.addRateObserver(for: episodeID)
            self.addTimeObserver()
        }

        if lastPosition > 0 {
            await MainActor.run {
                self.player?.seek(to: CMTime(seconds: lastPosition, preferredTimescale: 1)) { [weak self] _ in
                    guard let self = self else { return }
                    self.player?.playImmediately(atRate: self.playbackSpeed)
                }
            }
        } else {
            await MainActor.run {
                self.player?.playImmediately(atRate: self.playbackSpeed)
            }
        }

        // Defer metadata updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.updateNowPlayingInfo()
        }
    }
    
    private func setupPlayerItemObservations(_ playerItem: AVPlayerItem, for episodeID: String) {
        playerItemObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if item.isPlaybackLikelyToKeepUp {
                    print("🟢 Player item ready to keep up for episode: \(episodeID)")
                    // DON'T change state here - let rate observer handle it
                }
            }
        }
        
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    print("✅ Player item ready for episode: \(episodeID)")
                    // DON'T transition from loading here - wait for actual audio playback
                    
                case .failed:
                    let errorDescription = item.error?.localizedDescription ?? "unknown error"
                    print("❌ AVPlayerItem failed: \(errorDescription)")
                    
                    if let error = item.error as NSError?,
                       error.localizedDescription.contains("Cannot Complete Action") {
                        print("🔄 Attempting to recover from 'Cannot Complete Action' error")
                        
                        if case .loading(let id) = self.state, id == episodeID {
                            self.handlePlayerItemFailure(for: episodeID)
                        } else if case .playing(let id) = self.state, id == episodeID {
                            self.handlePlayerItemFailure(for: episodeID)
                        } else {
                            self.updateState(to: .idle)
                        }
                    } else {
                        // For other errors, only reset if we're loading this episode
                        if case .loading(let id) = self.state, id == episodeID {
                            print("❌ Abandoning playback attempt due to player item failure")
                            self.updateState(to: .idle)
                            self.cleanupPlayer()
                        }
                    }
                    
                case .unknown:
                    print("⚠️ AVPlayerItem status unknown for episode: \(episodeID)")
                
                @unknown default:
                    print("⚠️ Unknown AVPlayerItem status for episode: \(episodeID)")
                }
            }
        }
    }
    
    private func handlePlayerItemFailure(for episodeID: String) {
        guard let episode = currentEpisode, episode.id == episodeID else {
            print("❌ Cannot recover - episode mismatch or nil")
            updateState(to: .idle)
            cleanupPlayer()
            return
        }
        
        print("🔄 Attempting to recover playback for episode: \(episodeID)")
        
        // Save current position before recovery
        if let player = player {
            let currentPosition = player.currentTime().seconds
            if currentPosition > 0 {
                savePlaybackPosition(for: episode, position: currentPosition)
                print("💾 Saved position \(currentPosition) before recovery")
            }
        }
        
        // Clean up the failed player completely
        cleanupPlayer()
        
        // Check if this is a background-related failure or regular failure
        let currentState = state
        switch currentState {
        case .loading(let id) where id == episodeID:
            // Regular loading failure - retry once
            print("🔄 Regular loading failure - retrying once")
            retryPlayback(for: episode, episodeID: episodeID)
            
        case .playing(let id) where id == episodeID:
            // Was playing but failed - likely background related
            print("🔄 Playback failure during play - attempting recovery")
            retryPlayback(for: episode, episodeID: episodeID)
            
        default:
            print("⚠️ Unexpected state during failure recovery: \(currentState)")
            updateState(to: .idle)
        }
    }
    
    private func retryPlayback(for episode: Episode, episodeID: String) {
        // Set loading state for retry
        updateState(to: .loading(episodeID: episodeID))
        
        // Wait a moment for cleanup, then retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            // Double-check we're still trying to play this episode
            if case .loading(let currentID) = self.state, currentID == episodeID {
                print("🔄 Retrying playback after failure recovery")
                
                Task.detached(priority: .userInitiated) {
                    await self.play(episode: episode)
                }
            } else {
                print("⚠️ State changed during recovery delay - not retrying")
            }
        }
    }
    
    private func updateState(to newState: AudioPlayerState) {
        DispatchQueue.main.async {
            self.state = newState
        }
    }
    
    private func setupLoadingTimeout(for episodeID: String) {
        // Create a timeout that will clear the loading state after 10 seconds
        // only if we're still loading the same episode
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            
            if case .loading(let id) = self.state, id == episodeID {
                print("⚠️ Loading timeout triggered for episode \(episodeID)")
                
                // Force to playing state if we have a player
                if self.player != nil, self.player?.rate ?? 0 > 0 {
                    self.updateState(to: .playing(episodeID: episodeID))
                } else {
                    // Otherwise reset to idle
                    self.updateState(to: .idle)
                }
            }
        }
    }
    
    func pause() {
        guard let player = player, let episode = currentEpisode, let episodeID = episode.id else { return }
        
        // Check if player item is still valid before pausing
        if let currentItem = player.currentItem, currentItem.status == .failed {
            print("⚠️ Cannot pause - player item has failed")
            // Don't call pause() on a failed player, just update state
            updateState(to: .paused(episodeID: episodeID))
            return
        }
        
        savePlaybackPosition(for: episode, position: player.currentTime().seconds)
        player.pause() // This will trigger the rate observer to update state to paused
        
        updateNowPlayingInfo()
    }
    
    func stop() {
        if let player = player, let episode = currentEpisode {
            let currentPosition = player.currentTime().seconds
            savePlaybackPosition(for: episode, position: currentPosition)
        }
        
        // Clean up player completely
        cleanupPlayer()
        
        // Reset state variables
        progress = 0
        updateState(to: .idle)
        currentEpisode = nil
        
        // Clear now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        playerItemObservation?.invalidate()
        playerItemObservation = nil
        
        statusObservation?.invalidate()
        statusObservation = nil
        
        rateObserver?.invalidate() // Add this line
        rateObserver = nil         // Add this line
        
        // Use a more controlled teardown sequence
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }
    
    // MARK: - Time Control
    
    func seek(to time: Double) {
        guard let player = player else { return }
        
        let targetTime = CMTime(seconds: time, preferredTimescale: 1)
        isSeekingManually = true
        
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.progress = time
                self.isSeekingManually = false
                self.updateNowPlayingInfo()
            }
        }
    }
    
    func skipForward(seconds: Double) {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTime(seconds: currentTime.seconds + seconds, preferredTimescale: 1)
        player.seek(to: newTime)
    }
    
    func skipBackward(seconds: Double) {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTime(seconds: max(currentTime.seconds - seconds, 0), preferredTimescale: 1)
        player.seek(to: newTime)
    }
    
    func getProgress(for episode: Episode) -> Double {
        guard let currentEpisode = currentEpisode,
              let currentID = currentEpisode.id,
              let episodeID = episode.id,
              currentID == episodeID else {
            return episode.playbackPosition
        }
        
        return progress
    }
    
    func getActualDuration(for episode: Episode) -> Double {
        // Always prefer the saved actualDuration from Core Data
        if episode.actualDuration > 0 {
            return episode.actualDuration
        }
        
        // Only fall back to the player's duration if we don't have actualDuration saved yet
        // AND this is the currently playing episode
        if let currentEpisode = currentEpisode,
           let currentID = currentEpisode.id,
           let episodeID = episode.id,
           currentID == episodeID,
           let player = player,
           let currentItem = player.currentItem {
            
            let duration = currentItem.asset.duration
            let durationSeconds = CMTimeGetSeconds(duration)
            return durationSeconds.isNaN || durationSeconds <= 0 ? episode.duration : durationSeconds
        }
        
        // Final fallback to feed duration
        return episode.duration
    }
    
    func writeActualDuration(for episode: Episode) {
        // Skip if actualDuration appears to already be set
        if episode.actualDuration > 0 {
            print("⏩ Skipping duration load – already exists: \(episode.actualDuration) for \(episode.title ?? "Episode")")
            return
        }
        
        guard let urlString = episode.audio, let url = URL(string: urlString) else {
            print("❌ Invalid audio URL for duration extraction.")
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
                        print("✅ Actual duration saved: \(durationSeconds) for \(updatedEpisode.title ?? "Episode")")
                        
                        // If this is the current episode, update the player
                        if self.currentEpisode?.id == episode.id {
                            self.updateNowPlayingInfo()
                        }
                    }
                }
            } catch {
                print("⚠️ Failed to load actual duration: \(error.localizedDescription)")
            }
        }
    }
    
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
    
    func getElapsedTime(for episode: Episode) -> String {
        let elapsedTime = Int(getProgress(for: episode))
        return formatView(seconds: elapsedTime)
    }
    
    func getRemainingTime(for episode: Episode, pretty: Bool = true) -> String {
        // Get actual duration (already has fallbacks if not available)
        let duration = getActualDuration(for: episode)
        
        // Get current progress (already returns playbackPosition for non-playing episodes)
        let position = getProgress(for: episode)
        
        // Calculate remaining (always duration - position)
        let remaining = max(0, duration - position)
        let seconds = Int(remaining)
        
        // Format according to preference
        return pretty ? formatDuration(seconds: seconds) : formatView(seconds: seconds)
    }
    
    // MARK: - Playback Position
    
    private func savePlaybackPosition(for episode: Episode?, position: Double) {
        guard let episode = episode else { return }
        
        let objectID = episode.objectID
        
        // Use background context to avoid blocking main thread
        Task.detached(priority: .background) {
            let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
            
            backgroundContext.perform {
                do {
                    if let episodeInBackground = try backgroundContext.existingObject(with: objectID) as? Episode {
                        episodeInBackground.playbackPosition = position
                        
                        if backgroundContext.hasChanges {
                            try backgroundContext.save()
                        }
                    }
                } catch {
                    print("❌ Failed to save playback position: \(error)")
                }
            }
        }
    }
    
    private func savePlaybackPositionThrottled(for episode: Episode, position: Double) {
        lastSavedPosition = position
        
        // Cancel existing timer
        positionSaveTimer?.invalidate()
        
        // Set a timer to save after a brief delay (debouncing)
        positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.savePlaybackPosition(for: episode, position: position)
        }
    }
    
    func getSavedPlaybackPosition(for episode: Episode) -> Double {
        return episode.playbackPosition
    }
    
    func markAsPlayed(for episode: Episode, manually: Bool = false) {
        let context = episode.managedObjectContext ?? viewContext

        let isCurrentlyPlaying = (currentEpisode?.id == episode.id) && isPlaying
        let progressBeforeStop = isCurrentlyPlaying ? (player?.currentTime().seconds ?? 0) : episode.playbackPosition

        // Only stop and cleanup if this episode is currently playing
        if isCurrentlyPlaying {
            stop()
        }

        // Update state in memory
        episode.playbackPosition = 0
        episode.nowPlaying = false

        if episode.isPlayed {
            episode.isPlayed = false
            episode.playedDate = nil
        } else {
            episode.isPlayed = true
            episode.playedDate = Date.now

            let actualDuration = getActualDuration(for: episode)
            let playedTime = manually ? progressBeforeStop : actualDuration

            if let podcast = episode.podcast {
                podcast.playCount += 1
                podcast.playedSeconds += playedTime
                print("Recorded \(playedTime) seconds for \(episode.title ?? "episode")")
            }

            removeFromQueue(episode)

            // Only cleanup the player if it's still pointing to this episode
            if currentEpisode?.id == episode.id {
                cleanupPlayer()
            }
        }

        context.perform {
            do {
                try context.save()
                print("✅ Saved episode played state with position reset")
            } catch {
                print("❌ Error saving played state: \(error)")
                context.rollback()
            }
        }

        DispatchQueue.main.async {
            if self.currentEpisode?.id == episode.id {
                self.progress = 0
            }
            self.objectWillChange.send()
        }
    }
    
    private func addTimeObserver() {
        guard let player = player, let currentItem = player.currentItem else { return }

        Task {
            do {
                let duration = try await currentItem.asset.load(.duration)
                let durationSeconds = duration.seconds
                
                if let episode = currentEpisode, durationSeconds.isFinite && durationSeconds > 0 {
                    // Update episode's actual duration if needed
                    await MainActor.run {
                        if episode.actualDuration <= 0 || abs(episode.actualDuration - durationSeconds) > 1.0 {
                            episode.actualDuration = durationSeconds
                            try? episode.managedObjectContext?.save()
                            print("✅ Updated actual duration from player: \(durationSeconds) for \(episode.title ?? "Episode")")
                            updateNowPlayingInfo()
                        }
                    }
                }
            } catch {
                print("⚠️ Failed to load duration: \(error.localizedDescription)")
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 10),
            queue: .main
        ) { [weak self] time in
            guard let self = self,
                  let current = self.player?.currentItem,
                  let episode = self.currentEpisode,
                  current == player.currentItem else { return }

            let currentTime = time.seconds
            let roundedTime = floor(currentTime)
            let currentDuration = self.getActualDuration(for: episode)
            
            // Check if we're at the end of the episode
            if currentTime >= currentDuration - 0.2 {
                print("🎯 End of episode detected at \(currentTime) of \(currentDuration)")
                self.playerDidFinishPlaying(notification: Notification(name: .AVPlayerItemDidPlayToEndTime))
                return
            }
            
            if case .playing = self.state, self.progress != roundedTime {
                self.progress = roundedTime
                self.updateNowPlayingInfo()
                
                // Only save to Core Data every 5 seconds or significant changes
                if abs(roundedTime - self.lastSavedPosition) >= self.positionSaveThreshold {
                    self.savePlaybackPositionThrottled(for: episode, position: roundedTime)
                }
            }
        }
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        UserDefaults.standard.set(speed, forKey: "playbackSpeed")
        player?.rate = isPlaying ? speed : 0.0
        updateNowPlayingInfo()
    }
    
    func setForwardInterval(_ interval: Double) {
        forwardInterval = interval
        UserDefaults.standard.set(interval, forKey: "forwardInterval")
    }
    
    func setBackwardInterval(_ interval: Double) {
        backwardInterval = interval
        UserDefaults.standard.set(interval, forKey: "backwardInterval")
    }
    
    // MARK: - Audio Session
    private func configureAudioSession(activePlayback: Bool = false) {
        do {
            let session = AVAudioSession.sharedInstance()
            let options: AVAudioSession.CategoryOptions = activePlayback ? [] : [.mixWithOthers]
            try session.setCategory(.playback, mode: .default, options: options)

            if activePlayback {
                try session.setActive(true)
            }
        } catch {
            print("❌ Failed to set up AVAudioSession: \(error)")
        }
    }
    
    // MARK: - Remote Controls
    private func configureRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play command
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, let episode = self.currentEpisode else { return .commandFailed }
            
            Task {
                await self.play(episode: episode)
            }
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        // Disable next/previous track commands
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false

        // Enable 30s skip forward
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward(seconds: 30)
            return .success
        }

        // Enable 15s skip backward
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward(seconds: 15)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else { return }
        let duration = getActualDuration(for: episode)

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title ?? "Episode",
            MPMediaItemPropertyArtist: episode.podcast?.title ?? "Podcast",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPMediaItemPropertyPlaybackDuration: duration,
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
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo // ✅ ensure it's always set here
                }
            }
        }
    }
    private var cachedArtwork: MPMediaItemArtwork?

    private func fetchArtwork(for episode: Episode, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        if let cachedArtwork = cachedArtwork {
            completion(cachedArtwork)
            return
        }

        let imageUrls = [episode.episodeImage, episode.podcast?.image]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        guard let validImageUrl = imageUrls.first, let url = URL(string: validImageUrl) else {
            print("❌ No valid artwork URL for episode: \(episode.title ?? "Episode")")
            completion(nil)
            return
        }

        // Try Kingfisher cache first
        KingfisherManager.shared.cache.retrieveImage(forKey: url.cacheKey) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let value):
                if let cachedImage = value.image {
                    // Found in cache - create artwork immediately
                    let artwork = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in cachedImage }
                    self.cachedArtwork = artwork
                    completion(artwork)
                    print("✅ Using cached artwork for: \(episode.title ?? "Episode")")
                } else {
                    // Not in cache - download and cache it
                    self.downloadAndCacheArtwork(from: url, for: episode, completion: completion)
                }
            case .failure(let error):
                print("⚠️ Cache retrieval error: \(error.localizedDescription)")
                // Fallback to download
                self.downloadAndCacheArtwork(from: url, for: episode, completion: completion)
            }
        }
    }

    private func downloadAndCacheArtwork(from url: URL, for episode: Episode, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            
            if let error = error {
                print("⚠️ Artwork download error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data, let image = UIImage(data: data) else {
                print("⚠️ Failed to decode artwork from \(url.absoluteString)")
                completion(nil)
                return
            }

            // Cache the image in Kingfisher for future use
            KingfisherManager.shared.cache.store(image, forKey: url.cacheKey)
            print("✅ Cached artwork for future use: \(episode.title ?? "Episode")")

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.cachedArtwork = artwork
            completion(artwork)
        }.resume()
    }

    private func preloadArtwork(for episode: Episode) {
        let imageUrls = [episode.episodeImage, episode.podcast?.image]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        guard let validImageUrl = imageUrls.first, let url = URL(string: validImageUrl) else { return }

        // Check if already cached
        KingfisherManager.shared.cache.retrieveImage(forKey: url.cacheKey) { result in
            switch result {
            case .success(let value):
                if value.image == nil {
                    // Not cached, preload it
                    KingfisherManager.shared.retrieveImage(with: url) { result in
                        switch result {
                        case .success(let imageResult):
                            print("✅ Preloaded artwork for: \(episode.title ?? "Episode")")
                        case .failure(let error):
                            print("⚠️ Failed to preload artwork: \(error.localizedDescription)")
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }

    @objc private func handleAudioInterruption(notification: Notification) {
        guard let player = player, let episode = currentEpisode else { return }

        if let userInfo = notification.userInfo,
           let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
           let type = AVAudioSession.InterruptionType(rawValue: typeValue) {

            if type == .began {
                // Save position when audio is interrupted
                let currentPosition = player.currentTime().seconds
                savePlaybackPosition(for: currentEpisode, position: currentPosition)
                pause()
            } else if type == .ended {
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                    
                    Task {
                        await play(episode: episode)
                    }
                }
            }
        }
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            print("🔌 Audio route changed: old device unavailable (e.g., AirPods removed)")
            pause()
            
        case .categoryChange:
            print("⚙️ Audio category changed")

        case .newDeviceAvailable:
            print("🆕 New audio device available (e.g., plugged in)")

        default:
            break
        }
    }

    @objc private func savePlaybackOnExit() {
        guard let player = player, let episode = currentEpisode else { return }
        
        let currentPosition = player.currentTime().seconds
        savePlaybackPosition(for: episode, position: currentPosition)
    }
    
    @objc private func playerDidFinishPlaying(notification: Notification) {
        guard let finishedEpisode = currentEpisode else { return }
        print("🏁 Episode finished playing: \(finishedEpisode.title ?? "Episode")")
        
        // Store the finished episode info before clearing it
        let wasFinishedEpisode = finishedEpisode
        
        // Mark episode as played FIRST while we still have context
        wasFinishedEpisode.isPlayed = true
        wasFinishedEpisode.nowPlaying = false
        wasFinishedEpisode.playedDate = Date.now
        wasFinishedEpisode.playbackPosition = 0
        
        // Update podcast stats
        if let podcast = wasFinishedEpisode.podcast {
            podcast.playCount += 1
            podcast.playedSeconds += getActualDuration(for: wasFinishedEpisode)
        }
        
        // Remove from queue
        removeFromQueue(wasFinishedEpisode)
        
        // Save changes explicitly
        try? wasFinishedEpisode.managedObjectContext?.save()
        
        // Check for next episode BEFORE clearing current state
        let queuedEpisodes = fetchQueuedEpisodes()
        let nextEpisode = autoplayNext ? queuedEpisodes.first : nil
        
        // Now clean up current playback
        progress = 0
        updateState(to: .idle)
        cleanupPlayer()
        currentEpisode = nil
        
        // Clear now playing info temporarily
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // If we have a next episode, start it immediately
        if let nextEpisode = nextEpisode {
            print("🔄 Auto-playing next episode: \(nextEpisode.title ?? "Next Episode")")
            
            // Use togglePlayback instead of calling play directly
            // This ensures proper state management
            Task { @MainActor in
                // Small delay to ensure cleanup is complete
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                self.togglePlayback(for: nextEpisode)
            }
        }
    }

    @objc private func appDidEnterBackground() {
        guard let currentEpisode = currentEpisode else { return }
        
        logPlayerState(context: "appDidEnterBackground")
        
        // Save current state
        wasPlayingBeforeBackground = isPlaying
        lastKnownPosition = player?.currentTime().seconds ?? getSavedPlaybackPosition(for: currentEpisode)
        
        // Save position to Core Data
        savePlaybackPosition(for: currentEpisode, position: lastKnownPosition)
        
        print("📱 App backgrounded - saved position: \(lastKnownPosition), was playing: \(wasPlayingBeforeBackground), state: \(state)")
    }

    @objc private func appWillEnterForeground() {
        guard let currentEpisode = currentEpisode else { return }
        
        print("📱 App foregrounding - checking player state")
        logPlayerState(context: "appWillEnterForeground")
        
        // Ensure we're still dealing with the same episode
        guard let episodeID = currentEpisode.id else { return }
        
        // Check if player item is still valid
        if let player = player,
           let currentItem = player.currentItem {
            
            if currentItem.status == .failed {
                print("⚠️ Player item failed while backgrounded - will restart")
                handleBackgroundRecovery(for: currentEpisode)
            } else if wasPlayingBeforeBackground && player.rate == 0 {
                print("🔄 Resuming playback after background")
                // Update state first
                updateState(to: .playing(episodeID: episodeID))
                // Try to resume where we left off
                player.seek(to: CMTime(seconds: lastKnownPosition, preferredTimescale: 1)) { [weak self] _ in
                    guard let self = self else { return }
                    self.player?.playImmediately(atRate: self.playbackSpeed)
                    self.logPlayerState(context: "afterForegroundResume")
                }
            }
        } else if wasPlayingBeforeBackground {
            print("🔄 Player lost while backgrounded - restarting")
            handleBackgroundRecovery(for: currentEpisode)
        }
        
        // Reset background state
        wasPlayingBeforeBackground = false
    }

    private func handleBackgroundRecovery(for episode: Episode) {
        guard let episodeID = episode.id else { return }
        
        print("🔄 Handling background recovery for: \(episode.title ?? "Episode")")
        
        // Ensure we're still dealing with the same episode
        guard currentEpisode?.id == episodeID else {
            print("⚠️ Episode changed during background recovery - aborting")
            return
        }
        
        // Clean up the invalid player completely
        cleanupPlayer()
        
        // Use a dedicated recovery method instead of calling play() directly
        recoverPlaybackAfterBackground(for: episode)
    }
    
    private func recoverPlaybackAfterBackground(for episode: Episode) {
        guard let episodeID = episode.id else { return }
        
        // Set to loading state for recovery
        updateState(to: .loading(episodeID: episodeID))
        
        Task.detached(priority: .userInitiated) {
            // Validate we still have the same episode before recovery
            await MainActor.run {
                guard self.currentEpisode?.id == episodeID else {
                    print("⚠️ Episode changed during recovery task - aborting")
                    self.updateState(to: .idle)
                    return
                }
            }
            
            // Proceed with recovery
            await self.play(episode: episode)
        }
    }
    
    private func moveEpisodeToFrontOfQueue(_ episode: Episode) {
        // Ensure episode is in the queue by moving it to position 0
        if let context = episode.managedObjectContext {
            // Lock to prevent concurrent modifications
            queueLock.lock()
            defer { queueLock.unlock() }
            
            let queuePlaylist = getQueuePlaylist(context: context)
            
            // Ensure episode is in the queue
            if !episode.isQueued {
                episode.isQueued = true
                queuePlaylist.addToItems(episode)
            }
            
            // Get current queue order
            guard let items = queuePlaylist.items as? Set<Episode> else { return }
            let queue = items.sorted { $0.queuePosition < $1.queuePosition }
            
            // If this episode is already at position 0, no need to reorder
            if queue.first?.id == episode.id {
                return
            }
            
            // Create a new ordering by removing the episode and inserting at position 0
            var reordered = queue.filter { $0.id != episode.id }
            reordered.insert(episode, at: 0)
            
            // Update positions
            for (index, ep) in reordered.enumerated() {
                ep.queuePosition = Int64(index)
            }
            
            // Save changes
            do {
                try context.save()
                print("Episode moved to front of queue: \(episode.title ?? "Episode")")
            } catch {
                print("Error moving episode to front of queue: \(error.localizedDescription)")
                context.rollback()
            }
        }
    }
   
    private func playNextInQueue() {
        // This method is now only used for manual "play next" actions
        // Autoplay is handled directly in playerDidFinishPlaying
        let queuedEpisodes = fetchQueuedEpisodes()
        if let nextEpisode = queuedEpisodes.first {
            togglePlayback(for: nextEpisode)
        }
    }
    
    @MainActor
    private func saveEpisodeOnMainThread(_ episode: Episode) {
        guard let context = episode.managedObjectContext else { return }
        do {
            try context.save()
            print("✅ Saved episode state: \(episode.title ?? "")")
        } catch {
            print("❌ Failed to save episode: \(error)")
        }
    }
}

extension Float {
    func nonZeroOrDefault(_ defaultValue: Float) -> Float {
        return self == 0 ? defaultValue : self
    }
}
