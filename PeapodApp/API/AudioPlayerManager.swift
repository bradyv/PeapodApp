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
    private var playerItemObservation: NSKeyValueObservation?
    @Published var isPlaying: Bool = false
    @Published var progress: Double = 0
    @Published var currentEpisode: Episode?
    @Published var isLoading: Bool = false
    
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
        progress = 0
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
        loadPersistedCurrentEpisode()
    }
    
    func togglePlayback(for episode: Episode) {
        print("▶️ togglePlayback called for episode: \(episode.title ?? "Episode")")

        let context = episode.managedObjectContext

        // Case 1: episode is now playing and currently playing — pause
        if isPlayingEpisode(episode) {
            print("⏸ Already playing — pausing.")
            pause()
            return
        }

        // Case 2: episode is the current Now Playing — resume
        if episode.nowPlayingItem {
            print("▶️ Resuming playback on current episode")
            play(episode: episode)
            return
        }

        // Case 3: episode is new — promote to Now Playing
        if let id = episode.id {
            let request = Episode.fetchRequest()
            request.predicate = NSPredicate(format: "nowPlayingItem == YES AND id != %@", id)
            if let others = try? viewContext.fetch(request) {
                for other in others {
                    other.nowPlayingItem = false
                    other.isQueued = true
                }
                
                // Shift existing queued episodes down to make room
                var queue = fetchQueuedEpisodes()
                    .filter { $0.id != episode.id && $0.id != others.first?.id } // skip new nowPlaying + old nowPlaying (temporarily)
                    .sorted { $0.queuePosition < $1.queuePosition }
                
                if let requeued = others.first {
                    // Insert at front
                    requeued.queuePosition = 0
                    queue.insert(requeued, at: 0)
                }
                
                // Renumber everything to ensure sequential order
                for (index, ep) in queue.enumerated() {
                    ep.queuePosition = Int64(index)
                }
            }
        }

        episode.nowPlayingItem = true
        episode.isQueued = true

        try? context?.save()

        // NOW that everything is flushed, start playback
        play(episode: episode)
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        playerItemObservation?.invalidate()
        playerItemObservation = nil
        currentEpisode = nil
        persistCurrentEpisodeID(nil)
    }

    func play(episode: Episode) {
        guard let urlString = episode.audio,
              let url = URL(string: urlString) else {
            print("❌ Invalid audio URL")
            return
        }

        let previousEpisode = currentEpisode // 🧠 capture before overwrite

        let context = episode.managedObjectContext

        try? context?.save()

        // Step 3: Properly initialize player
        let shouldInitializePlayer = player == nil || previousEpisode?.id != episode.id

        if shouldInitializePlayer {
            cleanupPlayer()

            let playerItem = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: playerItem)

            cachedArtwork = nil
            addTimeObserver()

            isLoading = true

            playerItemObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    if item.isPlaybackLikelyToKeepUp {
                        self?.isLoading = false
                    }
                }
            }
        }
        
        currentEpisode = episode

        player?.play()
        isPlaying = true
        print("🎧 Playback started for \(episode.title ?? "Unknown")")
    }

    func pause() {
        guard let player = player else { return }
        savePlaybackPosition(for: currentEpisode, position: player.currentTime().seconds)
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func stop() {
        if let player = player {
            savePlaybackPosition(for: currentEpisode, position: player.currentTime().seconds)
        }
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        progress = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func getProgress(for episode: Episode) -> Double {
        guard let currentEpisode = currentEpisode, currentEpisode.id == episode.id else {
            return episode.playbackPosition
        }

        return progress
    }
    
    func isLoadingEpisode(_ episode: Episode) -> Bool {
        return isLoading && currentEpisode?.id == episode.id
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

                await MainActor.run {
                    if let updatedEpisode = try? viewContext.existingObject(with: objectID) as? Episode {
                        updatedEpisode.actualDuration = duration.seconds
                        try? updatedEpisode.managedObjectContext?.save()
                        print("✅ Actual duration saved: \(duration.seconds) for \(updatedEpisode.title ?? "Episode")")
                    }
                }
            } catch {
                print("⚠️ Failed to load actual duration: \(error.localizedDescription)")
            }
        }
    }

    func getStableRemainingTime(for episode: Episode, pretty: Bool = true) -> String {
        let actual = episode.actualDuration
        let feed = episode.duration
        let progress = getProgress(for: episode)

        let usingActual = actual > 0
        let playingOrResumed = isPlayingEpisode(episode) || hasStartedPlayback(for: episode)
        let duration = usingActual ? actual : feed

        let valueToShow: Double
        if usingActual && playingOrResumed && progress > 0 {
            valueToShow = max(0, actual - progress)
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
        let wasNowPlaying = episode.nowPlayingItem
        episode.playbackPosition = 0
        episode.isPlayed = true
        episode.isQueued = false
        episode.queuePosition = -1
        episode.nowPlayingItem = false
        episode.playedDate = Date.now
        episode.podcast?.playCount += 1

        let actualProgress = manually && currentEpisode?.id == episode.id
            ? min(player?.currentTime().seconds ?? 0, episode.duration)
            : min(episode.playbackPosition, episode.duration)

        let playedSecondsToAdd = manually ? actualProgress : episode.duration
        episode.podcast?.playedSeconds += playedSecondsToAdd

        if wasNowPlaying {
            currentEpisode = nil
            persistCurrentEpisodeID(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let next = fetchQueuedEpisodes().sorted(by: { $0.queuePosition < $1.queuePosition }).first {
                    next.nowPlayingItem = true
                    self.currentEpisode = next
                    self.persistCurrentEpisodeID(next.id)
                    try? next.managedObjectContext?.save()
                }
            }
        }

        try? episode.managedObjectContext?.save()
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
        let duration = episode.actualDuration > 0 ? episode.actualDuration : episode.duration

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
    
    private let currentEpisodeKey = "currentEpisodeID"

    func persistCurrentEpisodeID(_ id: String?) {
        UserDefaults.standard.set(id, forKey: currentEpisodeKey)
    }

    private func loadPersistedCurrentEpisode() {
        guard let idString = UserDefaults.standard.string(forKey: currentEpisodeKey),
              let uuid = UUID(uuidString: idString) else { return }
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        if let match = try? viewContext.fetch(request).first {
            currentEpisode = match
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
            } catch {
                print("⚠️ Failed to load duration: \(error.localizedDescription)")
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
            if self.isPlaying && self.progress != roundedTime {
                self.progress = roundedTime
                self.updateNowPlayingInfo()
                
                if let episode = self.currentEpisode {
                    self.savePlaybackPosition(for: episode, position: roundedTime)
                }
            }
        }
    }
}
