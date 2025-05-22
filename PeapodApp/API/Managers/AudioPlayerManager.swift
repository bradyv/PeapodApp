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

// MARK: - Background Context Helper
private func createBackgroundContext() -> NSManagedObjectContext {
    let context = PersistenceController.shared.container.newBackgroundContext()
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    return context
}

private func performBackgroundSave(_ operation: @escaping (NSManagedObjectContext) -> Void) {
    let context = createBackgroundContext()
    context.perform {
        operation(context)
        do {
            try context.save()
        } catch {
            print("❌ Background save error: \(error)")
            context.rollback()
        }
    }
}

private func performBackgroundSaveAsync(_ operation: @escaping (NSManagedObjectContext) async -> Void) {
    let context = createBackgroundContext()
    Task {
        await context.perform {
            Task {
                await operation(context)
                do {
                    try context.save()
                } catch {
                    print("❌ Background save error: \(error)")
                    context.rollback()
                }
            }
        }
    }
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
        configureAudioSession()
        configureRemoteTransportControls()
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(savePlaybackOnExit), name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    // MARK: - Core Playback Control
    func togglePlayback(for episode: Episode) {
        print("▶️ togglePlayback called for episode: \(episode.title ?? "Episode")")
        
        guard let episodeID = episode.id else { return }
        
        // Early exits for same episode
        switch state {
        case .playing(let id) where id == episodeID:
            print("⏸ Already playing — pausing.")
            pause()
            return
        case .loading(let id) where id == episodeID:
            print("⏳ Already loading — ignoring.")
            return
        default:
            break
        }
        
        // Set state/loading immediately to update UI
        DispatchQueue.main.async {
            self.state = .loading(episodeID: episodeID)
            self.currentEpisode = episode
        }
        
        Task {
            await self.play(episode: episode)
            
            // Update episode state in background
            await self.updateEpisodeStateOnPlayback(episode)
        }
    }
    
    private func updateEpisodeStateOnPlayback(_ episode: Episode) async {
        guard let episodeID = episode.id else { return }
        
        performBackgroundSave { context in
            guard let backgroundEpisode = try? context.existingObject(with: episode.objectID) as? Episode else { return }
            
            backgroundEpisode.nowPlaying = true
            if backgroundEpisode.isPlayed {
                backgroundEpisode.isPlayed = false
                backgroundEpisode.playedDate = nil
            }
        }
    }
    
    private func play(episode: Episode) async {
        guard let audio = episode.audio,
              let url = URL(string: audio),
              let episodeID = episode.id else {
            await MainActor.run {
                self.state = .idle
                self.currentEpisode = nil
            }
            return
        }
        
        // Prepare player item off-main-thread
        let playerItem = await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let item = AVPlayerItem(url: url)
                continuation.resume(returning: item)
            }
        }
        
        // Move episode to front of queue (background context)
        Task.detached(priority: .background) {
            await self.moveEpisodeToFrontOfQueueAsync(episode)
        }
        
        // Save previous episode state in background
        if let previous = currentEpisode, previous.id != episode.id {
            let previousPosition = player?.currentTime().seconds ?? 0
            
            Task.detached(priority: .background) {
                await self.savePlaybackPositionAsync(for: previous, position: previousPosition, markNotPlaying: true)
            }
        }
        
        let lastPosition = getSavedPlaybackPosition(for: episode)
        
        // Finalize player setup on main thread
        await MainActor.run {
            self.cleanupPlayer()
            let player = AVPlayer(playerItem: playerItem)
            self.cachedArtwork = nil
            self.player = player
            self.addTimeObserver()
            self.setupPlayerItemObservations(playerItem, for: episodeID)
            self.configureAudioSession(activePlayback: true)
            self.progress = lastPosition
            
            if lastPosition > 0 {
                player.seek(to: CMTime(seconds: lastPosition, preferredTimescale: 1)) { [weak self] _ in
                    guard let self = self else { return }
                    self.player?.playImmediately(atRate: self.playbackSpeed)
                    self.updateState(to: .playing(episodeID: episodeID))
                }
            } else {
                player.playImmediately(atRate: self.playbackSpeed)
                self.updateState(to: .playing(episodeID: episodeID))
            }
            
            print("🎧 Playback started for \(episode.title ?? "Episode")")
            self.updateNowPlayingInfo()
        }
        
        setupLoadingTimeout(for: episodeID)
        
        // Write actual duration in background
        Task.detached(priority: .background) {
            await self.writeActualDurationAsync(for: episode)
        }
    }
    
    private func moveEpisodeToFrontOfQueueAsync(_ episode: Episode) async {
        performBackgroundSave { context in
            guard let backgroundEpisode = try? context.existingObject(with: episode.objectID) as? Episode else { return }
            
            let queuePlaylist = getQueuePlaylist(context: context)
            
            // Ensure episode is in the queue
            if !backgroundEpisode.isQueued {
                backgroundEpisode.isQueued = true
                queuePlaylist.addToItems(backgroundEpisode)
            }
            
            // Get current queue order
            guard let items = queuePlaylist.items as? Set<Episode> else { return }
            let queue = items.sorted { $0.queuePosition < $1.queuePosition }
            
            // If this episode is already at position 0, no need to reorder
            if queue.first?.id == backgroundEpisode.id {
                return
            }
            
            // Create a new ordering by removing the episode and inserting at position 0
            var reordered = queue.filter { $0.id != backgroundEpisode.id }
            reordered.insert(backgroundEpisode, at: 0)
            
            // Update positions
            for (index, ep) in reordered.enumerated() {
                ep.queuePosition = Int64(index)
            }
            
            print("Episode moved to front of queue: \(backgroundEpisode.title ?? "Episode")")
        }
    }
    
    private func savePlaybackPositionAsync(for episode: Episode, position: Double, markNotPlaying: Bool = false) async {
        performBackgroundSave { context in
            guard let backgroundEpisode = try? context.existingObject(with: episode.objectID) as? Episode else { return }
            
            backgroundEpisode.playbackPosition = position
            if markNotPlaying {
                backgroundEpisode.nowPlaying = false
            }
        }
    }
    
    private func setupPlayerItemObservations(_ playerItem: AVPlayerItem, for episodeID: String) {
        // Observe when the player is ready for playback
        playerItemObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if item.isPlaybackLikelyToKeepUp {
                    // If we're still in loading state for this episode, update to playing
                    if case .loading(let id) = self.state, id == episodeID, self.player?.rate ?? 0 > 0 {
                        self.updateState(to: .playing(episodeID: episodeID))
                    }
                }
            }
        }
        
        // Also observe the player item status
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if item.status == .readyToPlay {
                    // If we're still in loading state for this episode, update to playing
                    if case .loading(let id) = self.state, id == episodeID, self.player?.rate ?? 0 > 0 {
                        self.updateState(to: .playing(episodeID: episodeID))
                    }
                } else if item.status == .failed {
                    // Handle error
                    print("❌ AVPlayerItem failed: \(item.error?.localizedDescription ?? "unknown error")")
                    
                    // If this is the current episode, reset state
                    if case .loading(let id) = self.state, id == episodeID {
                        self.updateState(to: .idle)
                    }
                }
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
        
        let currentPosition = player.currentTime().seconds
        
        // Save position in background
        Task.detached(priority: .background) {
            await self.savePlaybackPositionAsync(for: episode, position: currentPosition)
        }
        
        player.pause()
        
        // Update state to paused
        updateState(to: .paused(episodeID: episodeID))
        updateNowPlayingInfo()
    }
    
    func stop() {
        if let player = player, let episode = currentEpisode {
            let currentPosition = player.currentTime().seconds
            
            // Save position in background
            Task.detached(priority: .background) {
                await self.savePlaybackPositionAsync(for: episode, position: currentPosition)
            }
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
        
        // Use a more controlled teardown sequence
        if let player = self.player {
            player.pause()
            player.replaceCurrentItem(with: nil)
            self.player = nil
        }
    }
    
    // MARK: - Time Control
    
    func seek(to time: Double) {
        guard let player = player, let episode = currentEpisode, let episodeID = episode.id else { return }
        
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
        // If the episode is currently playing, use the player item's actual duration
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
        
        // Otherwise use the saved actual duration, falling back to the feed duration
        return episode.actualDuration > 0 ? episode.actualDuration : episode.duration
    }
    
    func writeActualDuration(for episode: Episode) {
        Task.detached(priority: .background) {
            await self.writeActualDurationAsync(for: episode)
        }
    }
    
    private func writeActualDurationAsync(for episode: Episode) async {
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
        
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = duration.seconds
            
            performBackgroundSave { context in
                guard let backgroundEpisode = try? context.existingObject(with: objectID) as? Episode else { return }
                backgroundEpisode.actualDuration = durationSeconds
                print("✅ Actual duration saved: \(durationSeconds) for \(backgroundEpisode.title ?? "Episode")")
            }
            
            // Update UI if this is the current episode
            await MainActor.run {
                if self.currentEpisode?.id == episode.id {
                    self.updateNowPlayingInfo()
                }
            }
        } catch {
            print("⚠️ Failed to load actual duration: \(error.localizedDescription)")
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
        
        // Save in background context
        Task.detached(priority: .background) {
            await self.savePlaybackPositionAsync(for: episode, position: position)
        }
    }
    
    func getSavedPlaybackPosition(for episode: Episode) -> Double {
        return episode.playbackPosition
    }
    
    func markAsPlayed(for episode: Episode, manually: Bool = false) {
        let isCurrentlyPlaying = (currentEpisode?.id == episode.id) && isPlaying
        let progressBeforeStop = isCurrentlyPlaying ? (player?.currentTime().seconds ?? 0) : episode.playbackPosition
        
        // Stop first, if necessary
        if isCurrentlyPlaying {
            stop()
        }
        
        // Update state in background
        Task.detached(priority: .background) {
            await self.markAsPlayedAsync(episode: episode, manually: manually, progressBeforeStop: progressBeforeStop)
        }
        
        // Update UI immediately
        DispatchQueue.main.async {
            if self.currentEpisode?.id == episode.id {
                self.progress = 0
            }
            self.objectWillChange.send()
        }
    }
    
    private func markAsPlayedAsync(episode: Episode, manually: Bool, progressBeforeStop: Double) async {
        performBackgroundSave { context in
            guard let backgroundEpisode = try? context.existingObject(with: episode.objectID) as? Episode else { return }
            
            // Update episode state
            backgroundEpisode.playbackPosition = 0
            backgroundEpisode.nowPlaying = false
            
            if backgroundEpisode.isPlayed {
                backgroundEpisode.isPlayed = false
                backgroundEpisode.playedDate = nil
            } else {
                backgroundEpisode.isPlayed = true
                backgroundEpisode.playedDate = Date.now
                
                let actualDuration = backgroundEpisode.actualDuration > 0 ? backgroundEpisode.actualDuration : backgroundEpisode.duration
                let playedTime = manually ? progressBeforeStop : actualDuration
                
                if let podcast = backgroundEpisode.podcast {
                    podcast.playCount += 1
                    podcast.playedSeconds += playedTime
                    print("Recorded \(playedTime) seconds for \(backgroundEpisode.title ?? "episode")")
                }
            }
            
            // Remove from queue if needed
            if backgroundEpisode.isQueued {
                let queuePlaylist = getQueuePlaylist(context: context)
                queuePlaylist.removeFromItems(backgroundEpisode)
                backgroundEpisode.isQueued = false
                backgroundEpisode.queuePosition = -1
                
                // Reindex remaining episodes
                let remainingEpisodes = (queuePlaylist.items as? Set<Episode> ?? [])
                    .sorted { $0.queuePosition < $1.queuePosition }
                
                for (index, ep) in remainingEpisodes.enumerated() {
                    ep.queuePosition = Int64(index)
                }
            }
            
            print("✅ Saved episode played state with position reset")
        }
        
        // Clean up player on main thread if needed
        await MainActor.run {
            if episode.id == self.currentEpisode?.id {
                self.cleanupPlayer()
            }
        }
    }
    
    private func addTimeObserver() {
        guard let player = player, let currentItem = player.currentItem else { return }
        
        Task {
            do {
                let duration = try await currentItem.asset.load(.duration)
                let durationSeconds = duration.seconds
                
                if let episode = currentEpisode, durationSeconds.isFinite && durationSeconds > 0 {
                    // Update episode's actual duration if needed in background
                    Task.detached(priority: .background) {
                        await self.updateActualDurationIfNeeded(episode: episode, duration: durationSeconds)
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
            // More precise end detection - within 0.2 seconds of the end
            if currentTime >= currentDuration - 0.2 {
                print("🎯 End of episode detected at \(currentTime) of \(currentDuration)")
                self.playerDidFinishPlaying(notification: Notification(name: .AVPlayerItemDidPlayToEndTime))
                return
            }
            
            if case .playing = self.state, self.progress != roundedTime {
                self.progress = roundedTime
                self.updateNowPlayingInfo()
                
                // Save position every second in background
                Task.detached(priority: .background) {
                    await self.savePlaybackPositionAsync(for: episode, position: roundedTime)
                }
            }
        }
    }
    
    private func updateActualDurationIfNeeded(episode: Episode, duration: Double) async {
        performBackgroundSave { context in
            guard let backgroundEpisode = try? context.existingObject(with: episode.objectID) as? Episode else { return }
            
            if backgroundEpisode.actualDuration <= 0 || abs(backgroundEpisode.actualDuration - duration) > 1.0 {
                backgroundEpisode.actualDuration = duration
                print("✅ Updated actual duration from player: \(duration) for \(backgroundEpisode.title ?? "Episode")")
            }
        }
        
        // Update UI
        await MainActor.run {
            self.updateNowPlayingInfo()
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
            try session.setActive(true)
        } catch {
            print("❌ Failed to set up AVAudioSession: \(error)")
        }
    }
    
    // MARK: - Remote Controls
    
    private func configureRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, let episode = self.currentEpisode, let episodeID = episode.id else { return .commandFailed }
            
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
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            
            if let error = error {
                print("⚠️ Artwork fetch error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                print("⚠️ Failed to decode artwork from \(validImageUrl)")
                completion(nil)
                return
            }
            
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.cachedArtwork = artwork
            completion(artwork)
        }.resume()
    }
    
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let player = player, let episode = currentEpisode, let episodeID = episode.id else { return }
        
        if let userInfo = notification.userInfo,
           let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
           let type = AVAudioSession.InterruptionType(rawValue: typeValue) {
            
            if type == .began {
                // Save position when audio is interrupted
                let currentPosition = player.currentTime().seconds
                
                // Save in background
                Task.detached(priority: .background) {
                    await self.savePlaybackPositionAsync(for: episode, position: currentPosition)
                }
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
        
        // Save in background - this is app termination so keep it simple
        Task.detached(priority: .background) {
            await self.savePlaybackPositionAsync(for: episode, position: currentPosition)
        }
    }
    
    @objc private func playerDidFinishPlaying(notification: Notification) {
       guard let finishedEpisode = currentEpisode else { return }
       print("🏁 Episode finished playing: \(finishedEpisode.title ?? "Episode")")
       
       // Store the finished episode info before clearing it
       let wasFinishedEpisode = finishedEpisode
       
       // Reset player state first
       progress = 0
       updateState(to: .idle)
       
       // Clean up player before doing queue operations
       cleanupPlayer()
       
       // Clear now playing info
       MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
       
       // Clear current episode reference
       currentEpisode = nil
       
       // Handle episode completion in background
       Task.detached(priority: .background) {
           await self.handleEpisodeCompletionAsync(wasFinishedEpisode)
           
           // Check for autoplay after completion handling
           if self.autoplayNext {
               await MainActor.run {
                   // Wait briefly to ensure queue updates are processed
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                       self.playNextInQueue()
                   }
               }
           }
       }
   }
    
    private func handleEpisodeCompletionAsync(_ episode: Episode) async {
        performBackgroundSave { context in
            guard let backgroundEpisode = try? context.existingObject(with: episode.objectID) as? Episode else { return }
            
            // Mark episode as played
            backgroundEpisode.isPlayed = true
            backgroundEpisode.nowPlaying = false
            backgroundEpisode.playedDate = Date.now
            
            // Update podcast stats
            if let podcast = backgroundEpisode.podcast {
                let actualDuration = backgroundEpisode.actualDuration > 0 ? backgroundEpisode.actualDuration : backgroundEpisode.duration
                podcast.playCount += 1
                podcast.playedSeconds += actualDuration
            }
            
            // Remove from queue
            if backgroundEpisode.isQueued {
                let queuePlaylist = getQueuePlaylist(context: context)
                queuePlaylist.removeFromItems(backgroundEpisode)
                backgroundEpisode.isQueued = false
                backgroundEpisode.queuePosition = -1
                
                // Reindex remaining episodes
                let remainingEpisodes = (queuePlaylist.items as? Set<Episode> ?? [])
                    .sorted { $0.queuePosition < $1.queuePosition }
                
                for (index, ep) in remainingEpisodes.enumerated() {
                    ep.queuePosition = Int64(index)
                }
            }
            
            // Reset playback position
            backgroundEpisode.playbackPosition = 0
            
            print("✅ Episode completion handled: \(backgroundEpisode.title ?? "Episode")")
        }
    }
   
   private func playNextInQueue() {
       let queuedEpisodes = fetchQueuedEpisodes()
       if let nextEpisode = queuedEpisodes.first {
           Task {
               await self.play(episode: nextEpisode)
           }
       }
   }
}

extension Float {
    func nonZeroOrDefault(_ defaultValue: Float) -> Float {
        return self == 0 ? defaultValue : self
    }
}
