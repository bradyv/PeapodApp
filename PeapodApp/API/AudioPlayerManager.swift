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
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerItemObservation: NSKeyValueObservation?
    @Published var isPlaying: Bool = false
    @Published var progress: Double = 0
    @Published var currentEpisode: Episode?
    @Published var isLoading: Bool = false
    @Published var playbackSpeed: Float = UserDefaults.standard.float(forKey: "playbackSpeed").nonZeroOrDefault(1.0)
    @Published var forwardInterval: Double = UserDefaults.standard.double(forKey: "forwardInterval") != 0 ? UserDefaults.standard.double(forKey: "forwardInterval") : 30
    @Published var backwardInterval: Double = UserDefaults.standard.double(forKey: "backwardInterval") != 0 ? UserDefaults.standard.double(forKey: "backwardInterval") : 15
    @Published var autoplayNext: Bool = UserDefaults.standard.bool(forKey: "autoplayNext")
    
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let player = player else { return }

        if let userInfo = notification.userInfo,
           let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
           let type = AVAudioSession.InterruptionType(rawValue: typeValue) {

            if type == .began {
                // ✅ Save position when audio is interrupted
                let currentPosition = player.currentTime().seconds
                savePlaybackPosition(for: currentEpisode, position: currentPosition)
                pause()
            } else if type == .ended {
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                    play(episode: currentEpisode!)
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
            // 🎧 E.g. AirPods removed
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
        guard let player = player else { return }
        
        let currentPosition = player.currentTime().seconds
        savePlaybackPosition(for: currentEpisode, position: currentPosition) // ✅ Save position before app is killed
    }
    
    @objc private func playerDidFinishPlaying(notification: Notification) {
        guard let finishedEpisode = currentEpisode else { return }
        print("🏁 Episode finished playing: \(finishedEpisode.title ?? "Episode")")
        
        // Store the finished episode info before clearing it
        let wasFinishedEpisode = finishedEpisode
        
        // Reset player state first
        progress = 0
        isPlaying = false
        
        // Clean up player before doing queue operations
        cleanupPlayer()
        
        // Clear now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // Mark episode as played after cleanup
        wasFinishedEpisode.isPlayed = true
        wasFinishedEpisode.nowPlaying = false
        wasFinishedEpisode.playedDate = Date.now
        
        // Update podcast stats
        if let podcast = wasFinishedEpisode.podcast {
            podcast.playCount += 1
            podcast.playedSeconds += getActualDuration(for: wasFinishedEpisode)
        }
        
        // Reset playback position
        wasFinishedEpisode.playbackPosition = 0
        
        // Use our dedicated function to remove from queue and save changes
        removeFromQueue(wasFinishedEpisode)
        
        // Save changes explicitly
        try? wasFinishedEpisode.managedObjectContext?.save()
        
        // Fetch the next episode AFTER removing the current one
        if autoplayNext {
            // Wait briefly to ensure queue updates are processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Check if there are more episodes in the queue to play next
                self.playNextInQueue()
            }
        }
    }
    
    private func playNextInQueue() {
        let queuedEpisodes = fetchQueuedEpisodes()
        if let nextEpisode = queuedEpisodes.first {
            self.play(episode: nextEpisode)
        }
    }
    
    private init() {
        configureAudioSession()
        configureRemoteTransportControls()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(savePlaybackOnExit), name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    func togglePlayback(for episode: Episode) {
        print("▶️ togglePlayback called for episode: \(episode.title ?? "Episode")")
        
        if episode.isPlayed {
            episode.isPlayed = false
            try? episode.managedObjectContext?.save()
            print("🗑️ Removed \(episode.title ?? "Episode") from played list")
        }

        // If it's already playing, pause
        if isPlayingEpisode(episode) {
            print("⏸ Already playing — pausing.")
            pause()
            return
        }

        // Otherwise, play
        play(episode: episode)
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        
        playerItemObservation?.invalidate()
        playerItemObservation = nil
    }

    func play(episode: Episode) {
        isLoading = true
        currentEpisode = episode

        // ✅ Yield to the main runloop without delay
        DispatchQueue.main.async {
            self.beginPlayback(for: episode)
        }
    }

    private func beginPlayback(for episode: Episode) {
        guard let audio = episode.audio, let url = URL(string: audio) else { return }

        // Do not update any other episode state yet — only playback setup
        cleanupPlayer()
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        cachedArtwork = nil
        addTimeObserver()
        
        playerItemObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.isPlaybackLikelyToKeepUp {
                    self?.isLoading = false
                }
            }
        }

        configureAudioSession(activePlayback: true)

        player?.playImmediately(atRate: playbackSpeed)
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    private func moveEpisodeToFrontOfQueue(_ episode: Episode) {
        // Ensure episode is in the queue by moving it to position 0
        moveEpisodeInQueue(episode, to: 0)
        
        // If there's a current episode that's different, ensure it's in position 1
        if let currentEp = currentEpisode, currentEp.id != episode.id, currentEp.isQueued {
            moveEpisodeInQueue(currentEp, to: 1)
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

    func pause() {
        guard let player = player else { return }
        savePlaybackPosition(for: currentEpisode, position: player.currentTime().seconds)
        player.pause()
        isPlaying = false
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
        isPlaying = false
        
        // Clear now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func getProgress(for episode: Episode) -> Double {
        guard let currentEpisode = currentEpisode, currentEpisode.id == episode.id else {
            return episode.playbackPosition
        }

        return progress
    }
    
    func isLoadingEpisode(_ episode: Episode) -> Bool {
        return isLoading && currentEpisode?.objectID == episode.objectID
    }

    func isPlayingEpisode(_ episode: Episode) -> Bool {
        return isPlaying && currentEpisode?.id == episode.id
    }

    func hasStartedPlayback(for episode: Episode) -> Bool {
        return getSavedPlaybackPosition(for: episode) > 0
    }
    
    func seek(to time: Double) {
        let targetTime = CMTime(seconds: time, preferredTimescale: 1)
        player?.seek(to: targetTime)
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
    
    func formatView(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds) // HH:MM:SS format
        } else {
            return String(format: "%02d:%02d", minutes, remainingSeconds) // MM:SS format
        }
    }
    
    func getActualDuration(for episode: Episode) -> Double {
        // If the episode is currently playing, use the player item's actual duration
        if currentEpisode?.id == episode.id, let player = player, let currentItem = player.currentItem {
            let duration = currentItem.asset.duration
            let durationSeconds = CMTimeGetSeconds(duration)
            return durationSeconds.isNaN || durationSeconds <= 0 ? episode.duration : durationSeconds
        }
        
        // Otherwise use the saved actual duration, falling back to the feed duration
        return episode.actualDuration > 0 ? episode.actualDuration : episode.duration
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

        Task {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = duration.seconds

                await MainActor.run {
                    if let updatedEpisode = try? viewContext.existingObject(with: objectID) as? Episode {
                        updatedEpisode.actualDuration = durationSeconds
                        try? updatedEpisode.managedObjectContext?.save()
                        print("✅ Actual duration saved: \(durationSeconds) for \(updatedEpisode.title ?? "Episode")")
                        
                        // If this is the current episode, update the player
                        if self.currentEpisode?.id == episode.id, let item = self.player?.currentItem {
                            self.updateNowPlayingInfo()
                        }
                    }
                }
            } catch {
                print("⚠️ Failed to load actual duration: \(error.localizedDescription)")
            }
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

    private func savePlaybackPosition(for episode: Episode?, position: Double) {
        guard let episode = episode else { return }
        episode.playbackPosition = position
        try? episode.managedObjectContext?.save()
    }

    func getSavedPlaybackPosition(for episode: Episode) -> Double {
        return episode.playbackPosition
    }
    
    func markAsPlayed(for episode: Episode, manually: Bool = false) {
        if episode.isPlayed {
            // Toggle off played state
            episode.isPlayed = false
            episode.playedDate = nil
        } else {
            // Set played state and update related properties
            episode.isPlayed = true
            episode.playedDate = Date.now
            
            // Get the actual duration we should record
            let actualDuration = getActualDuration(for: episode)
            let currentProgress: Double
            
            if manually {
                // If manually marking as played, use the current position if this is the active episode
                if currentEpisode?.id == episode.id {
                    currentProgress = player?.currentTime().seconds ?? episode.playbackPosition
                } else {
                    currentProgress = episode.playbackPosition
                }
            } else {
                // When automatically marking as played (natural end), use the full duration
                currentProgress = actualDuration
            }
            
            // Record play statistics
            if let podcast = episode.podcast {
                podcast.playCount += 1
                podcast.playedSeconds += manually ? currentProgress : actualDuration
                print("Recorded \(manually ? currentProgress : actualDuration) seconds for \(episode.title ?? "episode")")
            }
            
            // Use our dedicated function to remove from queue instead of doing it manually
            if episode.isQueued {
                removeFromQueue(episode)
            }
            
            // Reset playback state
            episode.nowPlaying = false
        }
        
        // Always reset playback position to 0 when marking played/unplayed
        episode.playbackPosition = 0
        
        // Save changes to persistence
        try? episode.managedObjectContext?.save()
        
        // If this was the currently playing episode, stop playback
        if currentEpisode?.id == episode.id {
            stop()
        }
    }

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

    private func configureRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play command
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, let episode = self.currentEpisode else { return .commandFailed }
            self.play(episode: episode)
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        // Disable next/previous track commands (<< / >>)
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
        } else {
            fetchArtwork(for: episode) { artwork in
                DispatchQueue.main.async {
                    if let artwork = artwork {
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                    }
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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

        URLSession.shared.dataTask(with: url) { data, _, error in
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
            // More precise end detection - within 0.2 seconds of the end
            if currentTime >= currentDuration - 0.2 {
                print("🎯 End of episode detected at \(currentTime) of \(currentDuration)")
                self.playerDidFinishPlaying(notification: Notification(name: .AVPlayerItemDidPlayToEndTime))
                return
            }
            
            if self.isPlaying && self.progress != roundedTime {
                self.progress = roundedTime
                self.updateNowPlayingInfo()
                
                // Save position every second
                self.savePlaybackPosition(for: episode, position: roundedTime)
            }
        }
    }
}

extension Float {
    func nonZeroOrDefault(_ defaultValue: Float) -> Float {
        return self == 0 ? defaultValue : self
    }
}
