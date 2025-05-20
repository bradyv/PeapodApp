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

// MARK: - AudioPlayerState enum
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

@MainActor
class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()
    
    // Player components
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerItemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    
    // State - only update on main thread
    @Published private(set) var state: AudioPlayerState = .idle {
        didSet {
            self.isPlaying = state.isPlaying
        }
    }
    @Published private(set) var isPlaying: Bool = false
    @Published var progress: Double = 0
    @Published var currentEpisode: Episode?
    
    // Settings
    @Published var playbackSpeed: Float = UserDefaults.standard.float(forKey: "playbackSpeed").nonZeroOrDefault(1.0)
    @Published var forwardInterval: Double = UserDefaults.standard.double(forKey: "forwardInterval").nonZeroOrDefault(30)
    @Published var backwardInterval: Double = UserDefaults.standard.double(forKey: "backwardInterval").nonZeroOrDefault(15)
    @Published var autoplayNext: Bool = UserDefaults.standard.bool(forKey: "autoplayNext")
    @Published var isSeekingManually: Bool = false
    
    // Queue integration
    private let queueManager = QueueManager.shared
    
    // Background context for Core Data operations
    private let backgroundContext: NSManagedObjectContext
    
    private init() {
        // Create dedicated background context
        self.backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        self.backgroundContext.parent = PersistenceController.shared.container.viewContext
        self.backgroundContext.automaticallyMergesChangesFromParent = false
        
        primePlayer()
        configureRemoteTransportControls()
        setupNotifications()
    }
    
    // MARK: - Player Setup and Cleanup
    
    private func primePlayer() {
        self.player = AVPlayer()
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
        
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }
    
    func togglePlayback(for episode: Episode) {
        print("▶️ togglePlayback called for episode: \(episode.title ?? "Episode")")
        guard let episodeID = episode.id else { return }
        
        // Handle same episode toggle immediately
        switch state {
        case .playing(let id) where id == episodeID:
            pause()
            return
        case .loading(let id) where id == episodeID:
            return
        default:
            break
        }
        
        // Store previous episode for queue management
        let previousEpisode = currentEpisode
        
        // Update UI state IMMEDIATELY for instant feedback
        self.state = .loading(episodeID: episodeID)
        self.currentEpisode = episode
        
        // Update queue immediately on main thread - instant UI feedback
        queueManager.addToFront(episode, pushingBack: previousEpisode)
        
        // Handle all playback setup asynchronously
        Task(priority: .userInitiated) {
            await self.setupAndPlay(episode: episode, episodeID: episodeID)
        }
    }
    
    private func setupAndPlay(episode: Episode, episodeID: String) async {
        // Validate audio URL in background
        guard let audio = episode.audio, let url = URL(string: audio) else {
            await MainActor.run {
                self.state = .idle
                self.currentEpisode = nil
            }
            return
        }
        
        // All heavy operations in background
        let playerItem = AVPlayerItem(url: url)
        let lastPosition = episode.playbackPosition
        
        // Update episode state in Core Data (background, no waiting)
        Task.detached(priority: .background) {
            await self.updateEpisodeForPlayback(episode)
        }
        
        // Configure audio session in background
        await configureAudioSessionBackground(activePlayback: true)
        
        // Return to main thread only for player setup
        await MainActor.run {
            self.cleanupPlayer()
            self.player?.replaceCurrentItem(with: playerItem)
            self.progress = lastPosition
            self.setupPlayerItemObservations(playerItem, for: episodeID)
            self.addTimeObserver()
            
            // Start playback immediately, seek asynchronously if needed
            if lastPosition > 0 {
                // Start playing immediately at current position, then seek
                self.player?.play()
                self.state = .playing(episodeID: episodeID)
                
                // Seek asynchronously without blocking
                self.player?.seek(to: CMTime(seconds: lastPosition, preferredTimescale: 1)) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.player?.rate = self?.playbackSpeed ?? 1.0
                    }
                }
            } else {
                self.player?.playImmediately(atRate: self.playbackSpeed)
                self.state = .playing(episodeID: episodeID)
            }
        }
        
        // Update now playing info after a brief delay, not blocking UI
        do {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        } catch {
            return
        }
        await MainActor.run {
            self.updateNowPlayingInfo()
        }
        
        // Setup loading timeout protection (background)
        Task.detached(priority: .background) {
            await self.setupLoadingTimeout(for: episodeID)
        }
    }
    
    private func setupLoadingTimeout(for episodeID: String) async {
        do {
            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        } catch {
            return
        }
        
        await MainActor.run {
            if case .loading(let id) = self.state, id == episodeID {
                print("⚠️ Loading timeout triggered for episode \(episodeID)")
                
                if self.player != nil, self.player?.rate ?? 0 > 0 {
                    self.state = .playing(episodeID: episodeID)
                } else {
                    self.state = .idle
                }
            }
        }
    }
    
    func pause() {
        guard let player = player, let episode = currentEpisode, let episodeID = episode.id else { return }
        
        // Stop playback immediately
        player.pause()
        state = .paused(episodeID: episodeID)
        updateNowPlayingInfo()
        
        // Save position in background - don't block UI
        let currentPosition = player.currentTime().seconds
        Task(priority: .background) {
            await self.savePlaybackPosition(episode: episode, position: currentPosition)
        }
    }
    
    func stop() {
        let currentPosition = player?.currentTime().seconds ?? 0
        let episodeToSave = currentEpisode
        
        // Clean up player immediately
        cleanupPlayer()
        
        // Reset state variables immediately
        progress = 0
        state = .idle
        currentEpisode = nil
        
        // Clear now playing info immediately
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // Save playback position in background if there was an episode
        if let episode = episodeToSave {
            Task(priority: .background) {
                await self.savePlaybackPosition(episode: episode, position: currentPosition)
            }
        }
    }
    
    private func setupPlayerItemObservations(_ playerItem: AVPlayerItem, for episodeID: String) {
        // Use a more efficient observation pattern
        playerItemObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if item.isPlaybackLikelyToKeepUp {
                    if case .loading(let id) = self.state, id == episodeID, self.player?.rate ?? 0 > 0 {
                        self.state = .playing(episodeID: episodeID)
                    }
                }
            }
        }
        
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if item.status == .readyToPlay {
                    if case .loading(let id) = self.state, id == episodeID, self.player?.rate ?? 0 > 0 {
                        self.state = .playing(episodeID: episodeID)
                    }
                } else if item.status == .failed {
                    print("❌ AVPlayerItem failed: \(item.error?.localizedDescription ?? "unknown error")")
                    if case .loading(let id) = self.state, id == episodeID {
                        self.state = .idle
                    }
                }
            }
        }
    }
    
    private func addTimeObserver() {
        guard let player = player, let currentItem = player.currentItem else { return }
        
        // Load and store actual duration asynchronously
        Task(priority: .background) {
            await self.loadAndStoreActualDuration(for: currentItem)
        }
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0, preferredTimescale: 10), // Reduced frequency
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
                self.playerDidFinishPlaying()
                return
            }
            
            if case .playing = self.state, self.progress != roundedTime {
                self.progress = roundedTime
                
                // Update now playing info less frequently
                if Int(roundedTime) % 5 == 0 {
                    self.updateNowPlayingInfo()
                }
                
                // Save position in background every 10 seconds instead of every second
                if Int(roundedTime) % 10 == 0 {
                    Task(priority: .background) {
                        await self.savePlaybackPosition(episode: episode, position: roundedTime)
                    }
                }
            }
        }
    }
    
    private func loadAndStoreActualDuration(for playerItem: AVPlayerItem) async {
        guard let episode = await MainActor.run(body: { self.currentEpisode }),
              episode.actualDuration <= 0 else { return }
        
        do {
            let duration = try await playerItem.asset.load(.duration)
            let durationSeconds = duration.seconds
            
            if durationSeconds.isFinite && durationSeconds > 0 {
                await updateActualDuration(for: episode, duration: durationSeconds)
                
                // Update now playing info if this is still the current episode
                await MainActor.run {
                    if self.currentEpisode?.id == episode.id {
                        self.updateNowPlayingInfo()
                    }
                }
            }
        } catch {
            print("⚠️ Failed to load duration: \(error.localizedDescription)")
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        guard let finishedEpisode = currentEpisode else { return }
        print("🏁 Episode finished playing: \(finishedEpisode.title ?? "Episode")")
        
        let actualDuration = getActualDuration(for: finishedEpisode)
        
        // Reset player state first
        progress = 0
        state = .idle
        
        // Clean up player
        cleanupPlayer()
        
        // Clear now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // Clear current episode reference immediately
        currentEpisode = nil
        
        // Remove from queue immediately for UI responsiveness
        queueManager.remove(finishedEpisode)
        
        // Handle episode completion in background
        Task(priority: .background) {
            await self.markEpisodeAsCompleted(finishedEpisode, duration: actualDuration)
            
            // Check for autoplay
            await MainActor.run {
                if self.autoplayNext, let nextEpisode = self.queueManager.first {
                    Task {
                        await self.setupAndPlay(episode: nextEpisode, episodeID: nextEpisode.id ?? "")
                    }
                }
            }
        }
    }
    
    // MARK: - Background Core Data Operations
    
    private func updateEpisodeForPlayback(_ episode: Episode) async {
        await performBackgroundCoreDataOperation { context in
            guard let bgEpisode = try context.existingObject(with: episode.objectID) as? Episode else { return }
            
            bgEpisode.nowPlaying = true
            if bgEpisode.isPlayed {
                bgEpisode.isPlayed = false
                bgEpisode.playedDate = nil
            }
        }
    }
    
    private func savePlaybackPosition(episode: Episode, position: Double) async {
        await performBackgroundCoreDataOperation { context in
            guard let bgEpisode = try context.existingObject(with: episode.objectID) as? Episode else { return }
            bgEpisode.playbackPosition = position
        }
    }
    
    private func markEpisodeAsCompleted(_ episode: Episode, duration: Double) async {
        await performBackgroundCoreDataOperation { context in
            guard let bgEpisode = try context.existingObject(with: episode.objectID) as? Episode else { return }
            
            bgEpisode.isPlayed = true
            bgEpisode.nowPlaying = false
            bgEpisode.playedDate = Date.now
            bgEpisode.playbackPosition = 0
            bgEpisode.isQueued = false
            bgEpisode.queuePosition = -1
            
            // Update podcast stats
            if let podcast = bgEpisode.podcast {
                podcast.playCount += 1
                podcast.playedSeconds += duration
            }
            
            // Remove from playlist relationship
            let queuePlaylist = self.getQueuePlaylist(context: context)
            queuePlaylist.removeFromItems(bgEpisode)
        }
    }
    
    private func updateActualDuration(for episode: Episode, duration: Double) async {
        await performBackgroundCoreDataOperation { context in
            guard let bgEpisode = try context.existingObject(with: episode.objectID) as? Episode else { return }
            
            if bgEpisode.actualDuration <= 0 || abs(bgEpisode.actualDuration - duration) > 1.0 {
                bgEpisode.actualDuration = duration
                print("✅ Actual duration saved: \(duration) for \(bgEpisode.title ?? "Episode")")
            }
        }
    }
    
    private func performBackgroundCoreDataOperation(_ operation: @escaping (NSManagedObjectContext) throws -> Void) async {
        await withCheckedContinuation { continuation in
            backgroundContext.perform {
                do {
                    try operation(self.backgroundContext)
                    try self.backgroundContext.save()
                    
                    // Merge changes to main context asynchronously
                    DispatchQueue.main.async {
                        do {
                            try PersistenceController.shared.container.viewContext.save()
                            continuation.resume()
                        } catch {
                            print("❌ Failed to save to persistent store: \(error)")
                            continuation.resume()
                        }
                    }
                } catch {
                    print("❌ Core Data operation failed: \(error)")
                    self.backgroundContext.rollback()
                    continuation.resume()
                }
            }
        }
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
        
        return episode.actualDuration > 0 ? episode.actualDuration : episode.duration
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
        
        Task(priority: .background) {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = duration.seconds
                
                await self.updateActualDuration(for: episode, duration: durationSeconds)
                
                // If this is the current episode, update the player on main thread
                await MainActor.run {
                    if self.currentEpisode?.id == episode.id {
                        self.updateNowPlayingInfo()
                    }
                }
            } catch {
                print("⚠️ Failed to load actual duration: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helper Methods for UI
    
    func isLoadingEpisode(_ episode: Episode) -> Bool {
        guard let id = episode.id else { return false }
        if case .loading(let episodeID) = state, episodeID == id {
            return true
        }
        return false
    }
    
    func isPlayingEpisode(_ episode: Episode) -> Bool {
        guard let id = episode.id else { return false }
        if case .playing(let episodeID) = state, episodeID == id {
            return true
        }
        return false
    }
    
    func hasStartedPlayback(for episode: Episode) -> Bool {
        return getSavedPlaybackPosition(for: episode) > 0
    }
    
    func getSavedPlaybackPosition(for episode: Episode) -> Double {
        return episode.playbackPosition
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
    
    func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm", minutes)
        } else {
            return String(format: "%ds", remainingSeconds)
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
        let duration = getActualDuration(for: episode)
        let position = getProgress(for: episode)
        let remaining = max(0, duration - position)
        let seconds = Int(remaining)
        return pretty ? formatDuration(seconds: seconds) : formatView(seconds: seconds)
    }
    
    // MARK: - Seek and Skip Controls
    
    func seek(to time: Double) {
        guard let player = player else { return }
        
        let targetTime = CMTime(seconds: time, preferredTimescale: 1)
        isSeekingManually = true
        
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
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
        print("Skipping forward to \(newTime)")
    }
    
    func skipBackward(seconds: Double) {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTime(seconds: max(currentTime.seconds - seconds, 0), preferredTimescale: 1)
        player.seek(to: newTime)
        print("Skipping back to \(newTime)")
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
    
    private func configureAudioSessionBackground(activePlayback: Bool = false) async {
        await Task.detached(priority: .userInitiated) {
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
        }.value
    }
    
    // MARK: - Remote Controls and Now Playing
    
    private func configureRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, let episode = self.currentEpisode else { return .commandFailed }
            
            Task {
                await self.setupAndPlay(episode: episode, episodeID: episode.id ?? "")
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: forwardInterval)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.skipForward(seconds: self?.forwardInterval ?? 30)
            }
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: backwardInterval)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.skipBackward(seconds: self?.backwardInterval ?? 15)
            }
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
            MPNowPlayingInfoPropertyMediaType: MPMediaType.audioBook.rawValue
        ]
        
        // Set artwork if available
        if let imageUrl = episode.episodeImage ?? episode.podcast?.image,
           !imageUrl.isEmpty,
           let url = URL(string: imageUrl) {
            
            Task(priority: .background) {
                await self.fetchAndSetArtwork(url: url, nowPlayingInfo: nowPlayingInfo)
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
    
    private func fetchAndSetArtwork(url: URL, nowPlayingInfo: [String: Any]) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            
            await MainActor.run {
                var updatedInfo = nowPlayingInfo
                updatedInfo[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
            }
        } catch {
            await MainActor.run {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
        }
    }
    
    // MARK: - Notifications and Handlers
    
    private func setupNotifications() {
            NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(savePlaybackOnExit), name: UIApplication.willTerminateNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        }
        
        @objc private func handleAudioInterruption(notification: Notification) {
            guard let player = player, let episode = currentEpisode else { return }
            
            if let userInfo = notification.userInfo,
               let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
               let type = AVAudioSession.InterruptionType(rawValue: typeValue) {
                
                if type == .began {
                    let currentPosition = player.currentTime().seconds
                    pause()
                } else if type == .ended {
                    if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
                       AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                        
                        Task {
                            await setupAndPlay(episode: episode, episodeID: episode.id ?? "")
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
                print("🔌 Audio route changed: old device unavailable")
                Task { @MainActor in
                    self.pause()
                }
            default:
                break
            }
        }
        
        @objc private func savePlaybackOnExit() {
            guard let player = player, let episode = currentEpisode else { return }
            
            let currentPosition = player.currentTime().seconds
            
            // Synchronous save for app termination
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.parent = PersistenceController.shared.container.viewContext
            
            do {
                if let managedEpisode = try context.existingObject(with: episode.objectID) as? Episode {
                    managedEpisode.playbackPosition = currentPosition
                    try context.save()
                    try PersistenceController.shared.container.viewContext.save()
                }
            } catch {
                print("❌ Error saving on exit: \(error)")
            }
        }
        
        // MARK: - Manual Episode Management
        
        func markAsPlayed(for episode: Episode, manually: Bool = false) {
            let isCurrentlyPlaying = (currentEpisode?.id == episode.id) && isPlaying
            let progressBeforeStop = isCurrentlyPlaying ? (player?.currentTime().seconds ?? 0) : episode.playbackPosition
            
            // Stop playback if this episode is currently playing
            if isCurrentlyPlaying {
                stop()
            }
            
            // Remove from queue immediately for UI responsiveness
            queueManager.remove(episode)
            
            // Update UI immediately for current episode
            if currentEpisode?.id == episode.id {
                self.progress = 0
            }
            
            // Handle Core Data updates in background
            Task(priority: .background) {
                await self.performBackgroundCoreDataOperation { context in
                    guard let bgEpisode = try context.existingObject(with: episode.objectID) as? Episode else { return }
                    
                    // Reset playback position and clear now playing
                    bgEpisode.playbackPosition = 0
                    bgEpisode.nowPlaying = false
                    bgEpisode.isQueued = false
                    bgEpisode.queuePosition = -1
                    
                    // Toggle played state
                    if bgEpisode.isPlayed {
                        bgEpisode.isPlayed = false
                        bgEpisode.playedDate = nil
                    } else {
                        bgEpisode.isPlayed = true
                        bgEpisode.playedDate = Date.now
                        
                        // Update podcast stats
                        let actualDuration = bgEpisode.actualDuration > 0 ? bgEpisode.actualDuration : bgEpisode.duration
                        let playedTime = manually ? progressBeforeStop : actualDuration
                        
                        if let podcast = bgEpisode.podcast {
                            podcast.playCount += 1
                            podcast.playedSeconds += playedTime
                        }
                    }
                    
                    // Remove from playlist relationship
                    let queuePlaylist = self.getQueuePlaylist(context: context)
                    queuePlaylist.removeFromItems(bgEpisode)
                }
            }
        }
        
        func toggleFav(_ episode: Episode) {
            Task(priority: .background) {
                await self.performBackgroundCoreDataOperation { context in
                    guard let bgEpisode = try context.existingObject(with: episode.objectID) as? Episode else { return }
                    bgEpisode.isFav.toggle()
                    
                    if bgEpisode.isFav {
                        bgEpisode.favDate = Date.now
                    } else {
                        bgEpisode.favDate = nil
                    }
                }
            }
        }
        
        private func getQueuePlaylist(context: NSManagedObjectContext) -> Playlist {
            let request: NSFetchRequest<Playlist> = Playlist.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", "Queue")
            
            if let existingPlaylist = try? context.fetch(request).first {
                return existingPlaylist
            } else {
                let newPlaylist = Playlist(context: context)
                newPlaylist.name = "Queue"
                try? context.save()
                return newPlaylist
            }
        }
    }

    extension Float {
        func nonZeroOrDefault(_ defaultValue: Float) -> Float {
            return self == 0 ? defaultValue : self
        }
    }

    extension Double {
        func nonZeroOrDefault(_ defaultValue: Double) -> Double {
            return self == 0 ? defaultValue : self
        }
    }
