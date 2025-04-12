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
    let request: NSFetchRequest<Episode> = Episode.fetchRequest()
    request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.id, ascending: true)]
    request.predicate = NSPredicate(format: "isQueued == YES")

    do {
        return try viewContext.fetch(request)
    } catch {
        print("⚠️ Failed to fetch queued episodes: \(error)")
        return []
    }
}

class AudioPlayerManager: ObservableObject, @unchecked Sendable {
    
    static let shared = AudioPlayerManager()
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    
    @Published var isPlaying: Bool = false
    @Published var progress: Double = 0
    @Published var duration: Double = 1
    @Published var currentEpisode: Episode?
    
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
        
        markAsPlayed(for: finishedEpisode)
        try? finishedEpisode.managedObjectContext?.save()
        stop()
    }
    
    private init() {
        configureAudioSession()
        configureRemoteTransportControls()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(savePlaybackOnExit), name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    private func duration(for episode: Episode) -> Int {
        if currentEpisode?.id == episode.id, duration > 1 {
            return Int(duration)
        } else {
            return Int(episode.duration)
        }
    }
    
    func togglePlayback(for episode: Episode) {
        print("▶️ togglePlayback called for episode: \(episode.title ?? "Episode")")
        
        // Remove from PlayedManager AFTER playback starts
        
        if episode.isPlayed {
            episode.isPlayed.toggle()
            try? episode.managedObjectContext?.save()
            print("🗑️ Removed \(episode.title ?? "Episode") from played list")
        }

        // If it's already playing, pause it
        if isPlayingEpisode(episode) {
            print("⏸ Already playing — pausing.")
            pause()
            return
        }

        // Save previous playback position
        if let current = currentEpisode, current.id != episode.id {
            let pos = player?.currentTime().seconds ?? 0
            savePlaybackPosition(for: current, position: pos)
            print("💾 Saved position for \(current.title ?? "Episode"): \(pos)s")
        }

        // Move episode to front of queue
        var queue = fetchQueuedEpisodes()
        // Remove the episode if it's already in the queue
        queue.removeAll { $0.id == episode.id }

        // Insert it at the front
        queue.insert(episode, at: 0)

        // Re-x episodes as queued
        for (index, ep) in queue.enumerated() {
            ep.isQueued = true
            ep.queuePosition = Int64(index)
        }
        try? viewContext.save()
        print("📦 Queued: \(episode.title ?? "Episode")")

        // Start playback
        play(episode: episode)
        print("🎧 Playback started for \(episode.title ?? "Episode")")
    }
    
    func moveToFront(_ episode: Episode) {
        var queue = fetchQueuedEpisodes()

        queue.removeAll { $0.id == episode.id }
        queue.insert(episode, at: 0)

        for (index, ep) in queue.enumerated() {
            ep.isQueued = true
            ep.queuePosition = Int64(index)
        }

        try? viewContext.save()
    }
    
    private func addToQueueAndPlay(_ episode: Episode) {
        var queue = fetchQueuedEpisodes()

        if let existingIndex = queue.firstIndex(where: { $0.id == episode.id }) {
            print("🔄 Moving episode to front of queue: \(episode.title ?? "Episode")")
            let existingEpisode = queue.remove(at: existingIndex)
            queue.insert(existingEpisode, at: 0)
        } else {
            print("🔄 Adding episode to front of queue: \(episode.title ?? "Episode")")
            queue.insert(episode, at: 0)
        }

        // ✅ Start playback
        play(episode: episode)
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }

    func play(episode: Episode) {
        guard let audio = episode.audio, let url = URL(string: audio) else { return }
        
        moveToFront(episode)

        if let previousEpisode = currentEpisode, previousEpisode.id != episode.id {
            savePlaybackPosition(for: previousEpisode, position: player?.currentTime().seconds ?? 0)
        }

        if currentEpisode?.id != episode.id {
            cleanupPlayer() // ✅ Properly dispose previous playback
            player = AVPlayer(url: url)
            currentEpisode = episode
            cachedArtwork = nil
            addTimeObserver()
        }

        let lastPosition = getSavedPlaybackPosition(for: episode)
        if lastPosition > 0 {
            player?.seek(to: CMTime(seconds: lastPosition, preferredTimescale: 1))
        }

        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        guard let player = player else { return }
        savePlaybackPosition(for: currentEpisode, position: player.currentTime().seconds)
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        progress = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func getProgress(for episode: Episode) -> Double {
        guard let currentEpisode = currentEpisode, currentEpisode.id == episode.id else {
            return getSavedPlaybackPosition(for: episode)
        }
        return progress
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
    
    func loadEpisodeMetadata(for episode: Episode) {
        guard let url = URL(string: episode.audio!) else {
            print("❌ Invalid URL: \(episode.audio ?? "Episode")")
            return
        }

        let objectID = episode.objectID
        let isCurrentEpisode = episode.id == currentEpisode?.id

        let asset = AVURLAsset(url: url)

        Task {
            do {
                let duration = try await asset.load(.duration)

                // Work with Core Data on the main context thread
                await MainActor.run {
                    if let updatedEpisode = try? viewContext.existingObject(with: objectID) as? Episode {
                        updatedEpisode.duration = duration.seconds
                        if isCurrentEpisode {
                            self.duration = duration.seconds
                        }
                        try? updatedEpisode.managedObjectContext?.save()
                        print("🎵 Loaded Actual Episode Duration: \(duration.seconds)")
                    }
                }
            } catch {
                print("⚠️ Failed to load episode duration: \(error.localizedDescription)")
            }
        }
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
    
    func getRemainingTime(for episode: Episode) -> String {
        let remainingTime = max(0, duration(for: episode) - Int(getProgress(for: episode)))
        return formatView(seconds: remainingTime)
    }

    func getRemainingTimePretty(for episode: Episode) -> String {
        let remainingTime = max(0, duration(for: episode) - Int(getProgress(for: episode)))
        return formatDuration(seconds: remainingTime)
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
            episode.isPlayed = false
            episode.playedDate = nil
        } else {
            episode.playbackPosition = 0
            episode.isPlayed = true
            episode.isQueued = false
            episode.playedDate = Date.now
            episode.podcast?.playCount += 1

            let actualProgress = manually && currentEpisode?.id == episode.id
                ? min(player?.currentTime().seconds ?? 0, episode.duration)
                : min(episode.playbackPosition, episode.duration)

            let playedSecondsToAdd = manually ? actualProgress : episode.duration
            episode.podcast?.playedSeconds += playedSecondsToAdd
            print("Recorded \(playedSecondsToAdd) for \(episode.title ?? "episode")")
        }

        try? episode.managedObjectContext?.save()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up AVAudioSession: \(error)")
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

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title ?? "Episode",
            MPMediaItemPropertyArtist: episode.podcast?.title ?? "Podcast",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
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
                DispatchQueue.main.async {
                    self.duration = duration.seconds
                }
            } catch {
                print("⚠️ Failed to load duration: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.duration = 1 // Default fallback
                }
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            guard let self = self,
                  let current = self.player?.currentItem,
                  current == player.currentItem else { return }

            let roundedTime = floor(time.seconds)
            if self.progress != roundedTime {
                self.progress = roundedTime
                self.updateNowPlayingInfo()
            }
        }
    }
}
