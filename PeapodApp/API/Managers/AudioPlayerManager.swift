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

class AudioPlayerManager: ObservableObject, @unchecked Sendable {
    static let shared = AudioPlayerManager()
    
    // MARK: - Player
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    
    // MARK: - Artwork Cache
    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkURL: String?
    
    // MARK: - Current Episode
    private(set) var currentEpisode: Episode? {
        didSet {
            if oldValue?.id != currentEpisode?.id {
                objectWillChange.send()
                updateNowPlayingInfo()
            }
        }
    }
    
    // MARK: - Computed State (derived from AVPlayer)
    var isPlaying: Bool {
        guard let player = player,
              let item = player.currentItem,
              item.status == .readyToPlay else {
            return false
        }
        return player.rate > 0
    }
    
    var isLoading: Bool {
        guard let item = player?.currentItem else { return false }
        return item.status == .unknown
    }
    
    var currentTime: Double {
        player?.currentTime().seconds ?? currentEpisode?.playbackPosition ?? 0
    }
    
    var duration: Double {
        // Prefer actual duration from player
        if let playerDuration = player?.currentItem?.duration.seconds,
           playerDuration.isFinite && playerDuration > 0 {
            return playerDuration
        }
        // Fallback to cached actual duration
        if let actualDuration = currentEpisode?.actualDuration, actualDuration > 0 {
            return actualDuration
        }
        // Last resort: feed duration
        return currentEpisode?.duration ?? 0
    }
    
    // MARK: - Settings
    @Published var playbackSpeed: Float = UserDefaults.standard.float(forKey: "playbackSpeed").nonZeroOrDefault(1.0) {
        didSet {
            UserDefaults.standard.set(playbackSpeed, forKey: "playbackSpeed")
            if isPlaying {
                player?.rate = playbackSpeed
            }
            updateNowPlayingInfo()
        }
    }
    
    @Published var forwardInterval: Double = UserDefaults.standard.double(forKey: "forwardInterval").nonZeroOrDefault(30) {
        didSet {
            UserDefaults.standard.set(forwardInterval, forKey: "forwardInterval")
            updateRemoteCommandIntervals()
        }
    }
    
    @Published var backwardInterval: Double = UserDefaults.standard.double(forKey: "backwardInterval").nonZeroOrDefault(15) {
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
    
    // MARK: - Initialization
    
    private init() {
        setupRemoteCommands()
        setupAppLifecycleNotifications()
        setupAudioSessionNotifications()
        restoreCurrentEpisode()
    }
    
    // MARK: - Playback Control
    
    func togglePlayback(for episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
        LogManager.shared.info("🎵 togglePlayback called for: \(episode.title ?? "Unknown")")
        
        // 🆕 Prewarm the preferred asset (local or remote)
        if let url = episode.preferredAudioURL {
            let asset = AVURLAsset(url: url)
            Task.detached(priority: .background) {
                do {
                    _ = try await asset.load(.isPlayable)
                    LogManager.shared.debug("🔥 Prewarmed asset for \(episode.title ?? "Unknown")")
                } catch {
                    LogManager.shared.warning("⚠️ Prewarm failed: \(error.localizedDescription)")
                }
            }
        }
        
        // Already playing this episode - toggle pause
        if currentEpisode?.id == episode.id {
            if isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }
        
        // Play new episode
        play(episode, episodesViewModel: episodesViewModel)
    }
    
    private func play(_ episode: Episode, episodesViewModel: EpisodesViewModel? = nil) {
        // Use preferred audio URL (local file if downloaded, otherwise remote)
        guard let url = episode.preferredAudioURL else {
            LogManager.shared.error("❌ No audio URL available for episode: \(episode.title ?? "Unknown")")
            return
        }
        
        // Log whether we're using local or remote
        if episode.isDownloaded {
            LogManager.shared.info("📱 Playing from local file: \(episode.title ?? "Unknown")")
        } else {
            LogManager.shared.info("🌐 Streaming from remote URL: \(episode.title ?? "Unknown")")
        }
        
        // Create player
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 1
        
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = false
        
        // Start playback IMMEDIATELY
        player?.playImmediately(atRate: playbackSpeed)
        
        // Update state
        currentEpisode = episode
        MPNowPlayingInfoCenter.default().playbackState = .playing
        objectWillChange.send()
        
        // Setup observers (lightweight)
        setupPlayerObservations(for: playerItem, episodeID: episode.id ?? "")
        
        // Everything slow happens AFTER playback starts
        Task {
            // Seek to saved position asynchronously
            if episode.playbackPosition > 0 {
                let targetTime = CMTime(seconds: episode.playbackPosition, preferredTimescale: 600)
                await self.player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                
                await MainActor.run {
                    self.updateNowPlayingInfo()
                }
            }
            
            // Update Core Data in background
            let context = PersistenceController.shared.container.newBackgroundContext()
            await context.perform {
                if let bgEpisode = context.object(with: episode.objectID) as? Episode {
                    bgEpisode.nowPlaying = true
                    
                    if !bgEpisode.isQueued {
                        bgEpisode.isQueued = true
                        Task { @MainActor in
                            episodesViewModel?.fetchQueue()
                        }
                    }
                    
                    try? context.save()
                }
            }
        }
    }
    
    private func pause() {
        player?.pause()
        
        // Verify player actually stopped before updating control center
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            if self.player?.rate == 0 {
                MPNowPlayingInfoCenter.default().playbackState = .paused
            } else {
                // Force stop if still playing
                self.player?.rate = 0
                MPNowPlayingInfoCenter.default().playbackState = .paused
            }
            
            self.updateNowPlayingInfo()
        }
        
        savePositionSync()
        objectWillChange.send()
    }
    
    private func resume() {
        // Ensure we have a valid player
        guard let player = player,
              let currentItem = player.currentItem,
              currentItem.status == .readyToPlay else {
            // No valid player - restart playback
            if let episode = currentEpisode {
                play(episode)
            }
            return
        }
        
        player.rate = playbackSpeed
        MPNowPlayingInfoCenter.default().playbackState = .playing
        updateNowPlayingInfo()
        objectWillChange.send()
    }
    
    func stop() {
        LogManager.shared.info("🛑 Stop called")
        LogManager.shared.info("🛑 Current player: \(player != nil ? "exists" : "nil")")
        LogManager.shared.info("🛑 Current item status: \(player?.currentItem?.status.rawValue ?? -1)")
        
        savePositionSync()
        
        // Clear nowPlaying flag
        if let episode = currentEpisode {
            let context = PersistenceController.shared.container.viewContext
            context.perform {
                episode.nowPlaying = false
                try? context.save()
            }
        }
        
        // Cleanup player
        timeObserver.map { player?.removeTimeObserver($0) }
        timeObserver = nil
        
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        
        currentEpisode = nil
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        objectWillChange.send()
        
        LogManager.shared.info("🛑 Stop complete, player cleared")
    }
    
    // MARK: - Seeking
    
    func seek(to time: Double) {
        guard let player = player else { return }
        
        isSeekingManually = true
        objectWillChange.send()
        
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.isSeekingManually = false
            self?.savePosition()
            self?.objectWillChange.send()
            // Only update Now Playing after manual seek to sync scrubber
            self?.updateNowPlayingInfo()
        }
    }
    
    func skipForward() {
        let newTime = min(currentTime + forwardInterval, duration)
        seek(to: newTime)
    }
    
    func skipBackward() {
        let newTime = max(currentTime - backwardInterval, 0)
        seek(to: newTime)
    }
    
    // MARK: - Player Observations
    
    private func setupPlayerObservations(for playerItem: AVPlayerItem, episodeID: String) {
        LogManager.shared.info("👀 Setting up observations for episode: \(episodeID)")
        
        // Clean up previous
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        
        // Status observer - fires when player is ready to play
        let statusObserver = playerItem.observe(\.status, options: [.new, .old]) { [weak self] item, change in
            let oldValue = change.oldValue?.rawValue ?? -1
            let newValue = item.status.rawValue
            LogManager.shared.info("📊 Status changed: \(oldValue) -> \(newValue) (0=unknown, 1=ready, 2=failed)")
            
            if item.status == .failed {
                if let error = item.error {
                    LogManager.shared.error("❌ Player item FAILED: \(error)")
                    LogManager.shared.error("❌ Error domain: \(error._domain), code: \(error._code)")
                }
            }
            
            guard let self = self,
                  item.status == .readyToPlay,
                  let player = self.player,
                  player.rate > 0 else { return }
            
            LogManager.shared.info("📊 Status is readyToPlay, rate: \(self.player?.rate ?? -1)")
            
            DispatchQueue.main.async {
                print("🎵 Player ready and playing - updating Now Playing Info")
                self.updateNowPlayingInfo()
            }
        }
        observations.append(statusObserver)
        
        // Rate observer - triggers UI updates when playback rate changes (play/pause)
        if let player = player {
            let rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
            observations.append(rateObserver)
            
            // TimeControlStatus observer - critical for seeing stalls
            let timeControlObserver = player.observe(\.timeControlStatus, options: [.new, .old]) { player, change in
                let oldValue = change.oldValue?.rawValue ?? -1
                let newValue = player.timeControlStatus.rawValue
                LogManager.shared.info("⏱️ TimeControlStatus changed: \(oldValue) -> \(newValue) (0=paused, 1=waitingToPlay, 2=playing)")
                
                if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    if let reason = player.reasonForWaitingToPlay {
                        LogManager.shared.warning("⚠️ Waiting reason: \(reason.rawValue)")
                    }
                }
            }
            observations.append(timeControlObserver)
        }
        
        // Buffer state observers
        let bufferEmptyObserver = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { item, _ in
            if item.isPlaybackBufferEmpty {
                LogManager.shared.info("📭 Playback buffer is EMPTY")
            }
        }
        observations.append(bufferEmptyObserver)
        
        let bufferKeepUpObserver = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { item, _ in
            LogManager.shared.info("📶 Playback likely to keep up: \(item.isPlaybackLikelyToKeepUp)")
        }
        observations.append(bufferKeepUpObserver)
        
        // Duration observer - fires once when ready
        let durationObserver = playerItem.observe(\.duration, options: [.new]) { [weak self] item, _ in
            let seconds = item.duration.seconds
            guard seconds.isFinite && seconds > 0 else { return }
            
            LogManager.shared.info("⏱️ Duration available: \(seconds)s")
            
            // Cache actual duration in Core Data
            Task { @MainActor in
                if let episode = self?.currentEpisode, episode.id == episodeID {
                    let context = PersistenceController.shared.container.viewContext
                    context.perform {
                        episode.actualDuration = seconds
                        try? context.save()
                    }
                    self?.objectWillChange.send()
                }
            }
        }
        observations.append(durationObserver)
        
        // Episode completion - system notification
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard self?.currentEpisode?.id == episodeID else { return }
            LogManager.shared.info("🏁 Episode completed")
            self?.handleEpisodeCompletion()
        }
        
        // Failed to play to end time
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                LogManager.shared.error("❌ Failed to play to end: \(error)")
            }
            self?.savePositionSync()
        }
        
        // Playback stalled
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: playerItem,
            queue: .main
        ) { _ in
            LogManager.shared.warning("⚠️ Playback stalled!")
        }
        
        // Periodic time observer for position saving and UI updates
        let interval = UIApplication.shared.applicationState == .background ? 2.0 : 0.5
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 10),
            queue: .main
        ) { [weak self] _ in
            guard let self = self,
                  self.currentEpisode?.id == episodeID,
                  !self.isSeekingManually else { return }
            
            self.objectWillChange.send()
            self.savePosition() // Save every interval
        }
        
        LogManager.shared.info("✅ All observations set up")
    }
    
    // MARK: - Position Saving
    
    private func savePosition() {
        guard let episode = currentEpisode else { return }
        
        let position = currentTime
        let context = PersistenceController.shared.container.viewContext
        
        context.perform {
            episode.playbackPosition = position
            
            if context.hasChanges {
                try? context.save()
            }
        }
    }
    
    func savePositionSync() {
        guard let episode = currentEpisode else { return }
        let position = currentTime
        
        let context = PersistenceController.shared.container.viewContext
        context.performAndWait {
            episode.playbackPosition = position
            if context.hasChanges {
                try? context.save()
            }
        }
    }
    
    // MARK: - Episode Completion
    
    private func handleEpisodeCompletion() {
        guard let episode = currentEpisode else { return }
        
        LogManager.shared.info("Episode completed: \(episode.title ?? "Unknown")")
        
        let context = PersistenceController.shared.container.viewContext
        context.perform {
            // Mark as played
            episode.isPlayed = true
            episode.playedDate = Date()
            episode.playbackPosition = 0
            episode.nowPlaying = false
            
            // Remove from queue
            episode.isQueued = false
            
            // Update podcast stats
            if let podcast = episode.podcast {
                podcast.playCount += 1
                podcast.playedSeconds += self.duration
            }
            
            try? context.save()
        }
        
        // Clear player
        stop()
        
        // Autoplay next
        if autoplayNext {
            Task { @MainActor in
                if let next = fetchNextQueuedEpisode() {
                    LogManager.shared.info("Autoplaying next: \(next.title ?? "Unknown")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.play(next)
                    }
                }
            }
        }
    }
    
    private func fetchNextQueuedEpisode() -> Episode? {
        let context = PersistenceController.shared.container.viewContext
        return getQueuedEpisodes(context: context).first
    }
    
    // MARK: - Manual Mark as Played
    
    func markAsPlayed(for episode: Episode, manually: Bool = false) {
        let isCurrentEpisode = currentEpisode?.id == episode.id
        let playedTime = isCurrentEpisode ? currentTime : episode.playbackPosition
        
        // Stop if currently playing
        if isCurrentEpisode {
            stop()
        }
        
        let context = PersistenceController.shared.container.viewContext
        context.perform {
            episode.isPlayed = true
            episode.playedDate = Date()
            episode.playbackPosition = 0
            episode.nowPlaying = false
            episode.isQueued = false
            
            if let podcast = episode.podcast {
                podcast.playCount += 1
                podcast.playedSeconds += manually ? playedTime : (episode.actualDuration > 0 ? episode.actualDuration : episode.duration)
            }
            
            try? context.save()
        }
        
        objectWillChange.send()
    }
    
    func markAsUnplayed(for episode: Episode) {
        let context = PersistenceController.shared.container.viewContext
        context.perform {
            episode.isPlayed = false
            episode.playedDate = nil
            try? context.save()
        }
        
        objectWillChange.send()
    }
    
    // MARK: - App Lifecycle Notifications
    
    private func setupAppLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        savePositionSync()
        updateNowPlayingInfo()
    }
    
    @objc private func appWillResignActive() {
        savePositionSync()
    }
    
    @objc private func appWillTerminate() {
        savePositionSync()
        updateNowPlayingInfo()
    }
    
    // MARK: - Audio Session Notifications
    
    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // CRITICAL: Save position IMMEDIATELY when interruption starts
            savePositionSync()
            LogManager.shared.info("🔴 Audio interrupted - position saved")
            
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                // Resume playback if user expects it
                resume()
            }
            
            // Update Now Playing Info after interruption ends
            updateNowPlayingInfo()
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // CRITICAL: Device disconnected (AirPods removed, CarPlay disconnected)
            savePositionSync()
            pause()
            LogManager.shared.info("🎧 Audio route changed (device unavailable) - position saved and paused")
            
        case .newDeviceAvailable:
            LogManager.shared.info("🎧 New audio device available")
            
        default:
            break
        }
    }
    
    // MARK: - Restore State
    
    private func restoreCurrentEpisode() {
        let context = PersistenceController.shared.container.viewContext
        
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "nowPlaying == YES")
        request.fetchLimit = 1
        
        if let episode = try? context.fetch(request).first {
            currentEpisode = episode
            LogManager.shared.info("Restored current episode: \(episode.title ?? "Unknown")")
        }
    }
    
    // MARK: - Now Playing Info
    // Only call this when episode changes, playback speed changes, or after manual seek
    
    func updateNowPlayingInfo() {
        guard let episode = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            cachedArtwork = nil
            cachedArtworkURL = nil
            return
        }
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title ?? "Episode",
            MPMediaItemPropertyArtist: episode.podcast?.title ?? "Podcast",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0.0
        ]
        
        // Use cached artwork if available
        if let cachedArtwork = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        
        // Load artwork only if we don't have it cached OR if URL changed
        let artworkURL = episode.episodeImage ?? episode.podcast?.image
        if cachedArtwork == nil || cachedArtworkURL != artworkURL {
            cachedArtworkURL = artworkURL
            fetchArtwork(for: episode) { [weak self] artwork in
                guard let self = self else { return }
                self.cachedArtwork = artwork
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
    
    private func fetchArtwork(for episode: Episode, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        guard let urlString = episode.episodeImage ?? episode.podcast?.image,
              let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let cacheKey = url.cacheKey
        KingfisherManager.shared.cache.retrieveImage(forKey: cacheKey) { result in
            switch result {
            case .success(let value):
                if let cachedImage = value.image {
                    // Cache hit - use immediately
                    let artwork = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in cachedImage }
                    completion(artwork)
                } else {
                    // Cache miss - fetch from network
                    self.fetchArtworkFromNetwork(url: url, completion: completion)
                }
            case .failure:
                // Cache error - fetch from network
                self.fetchArtworkFromNetwork(url: url, completion: completion)
            }
        }
    }

    private func fetchArtworkFromNetwork(url: URL, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        Task {
            do {
                let result = try await KingfisherManager.shared.retrieveImage(with: url)
                let artwork = MPMediaItemArtwork(boundsSize: result.image.size) { _ in result.image }
                await MainActor.run {
                    completion(artwork)
                }
            } catch {
                LogManager.shared.warning("Failed to fetch artwork: \(error)")
                await MainActor.run {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Remote Commands
    
    private func setupRemoteCommands() {
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
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }
        
        updateRemoteCommandIntervals()
    }
    
    private func updateRemoteCommandIntervals() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipForwardCommand.preferredIntervals = [forwardInterval as NSNumber]
        commandCenter.skipBackwardCommand.preferredIntervals = [backwardInterval as NSNumber]
    }
    
    // MARK: - Helper Methods (for UI compatibility)
    
    func getActualDuration(for episode: Episode) -> Double {
        if episode.id == currentEpisode?.id {
            return duration
        }
        return episode.actualDuration > 0 ? episode.actualDuration : episode.duration
    }
    
    func getProgress(for episode: Episode) -> Double {
        if episode.id == currentEpisode?.id {
            return currentTime
        }
        return episode.playbackPosition
    }
    
    func isPlayingEpisode(_ episode: Episode) -> Bool {
        currentEpisode?.id == episode.id && isPlaying
    }
    
    func isLoadingEpisode(_ episode: Episode) -> Bool {
        currentEpisode?.id == episode.id && isLoading
    }
    
    func hasStartedPlayback(for episode: Episode) -> Bool {
        episode.playbackPosition > 0
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
        formatView(seconds: Int(getProgress(for: episode)))
    }
    
    func getRemainingTime(for episode: Episode, pretty: Bool = true) -> String {
        let duration = getActualDuration(for: episode)
        let position = getProgress(for: episode)
        let remaining = max(0, duration - position)
        return formatDuration(seconds: Int(remaining))
    }
    
    func getStableRemainingTime(for episode: Episode, pretty: Bool = true) -> String {
        let duration = getActualDuration(for: episode)
        let progress = getProgress(for: episode)
        
        let hasBeenPlayed = isPlayingEpisode(episode) ||
                           isLoadingEpisode(episode) ||
                           hasStartedPlayback(for: episode) ||
                           progress > 0
        
        let valueToShow = hasBeenPlayed ? max(0, duration - progress) : duration
        if pretty {
            return formatDuration(seconds: Int(valueToShow))
        } else {
            return formatView(seconds: Int(valueToShow))
        }
    }
}

// MARK: - Extensions

extension Float {
    func nonZeroOrDefault(_ defaultValue: Float) -> Float {
        self == 0 ? defaultValue : self
    }
}

extension Double {
    func nonZeroOrDefault(_ defaultValue: Double) -> Double {
        self == 0 ? defaultValue : self
    }
}
