//
//  PPCircularProgress.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-15.
//

import SwiftUI

struct PPCircularProgress: View {
    @ObservedObject var player = AudioPlayerManager.shared
    @Binding var value: Double
    let range: ClosedRange<Double>
    var iconType: IconType = .playPause
    var progressColor: Color = .primary
    var backgroundOpacity: Double = 0.3
    var lineWidth: CGFloat? = nil
    
    enum IconType {
        case playPause
        case playOnly
        case pauseOnly
        case none
    }
    
    private var progress: Double {
        // Handle possible invalid range
        guard range.upperBound > range.lowerBound else { return 0 }
        
        // Normalize the value to be between 0 and 1
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return max(0, min(normalized, 1.0))
    }
    
    private var iconName: String {
        switch iconType {
        case .playPause:
            return player.isPlaying ? "pause.fill" : "play.fill"
        case .playOnly:
            return "play.fill"
        case .pauseOnly:
            return "pause.fill"
        case .none:
            return ""
        }
    }
    
    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(
                    progressColor.opacity(backgroundOpacity),
                    lineWidth: 2
                )
            
            // Progress track
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.1), value: progress)
            
            // Center icon
            if iconType != .none {
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundColor(progressColor)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PPCircularPlayButton: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var player = AudioPlayerManager.shared
    @ObservedObject var episode: Episode
    @State private var isPlaying = false
    @State private var isLoading = false
    @State private var playbackPosition: Double = 0
    @State private var episodePlayed: Bool = false
    var displayedInQueue: Bool = false
    
    // Styling options with defaults that match your app's design
    var buttonSize: CGFloat = 44
    var progressLineWidth: CGFloat? = nil
    var foregroundColor: Color = .background
    var backgroundColor: Color = .heading
    
    var body: some View {
        ZStack {
            if isLoading {
                // Show spinner when loading
                PPSpinner(color: displayedInQueue ? .black : foregroundColor)
                    .frame(width: buttonSize * 0.6, height: buttonSize * 0.6)
            } else if isPlaying {
                // Show circular progress with pause icon when playing
                PPCircularProgress(
                    value: Binding(
                        get: { playbackPosition },
                        set: { newValue in
                            playbackPosition = newValue
                            player.seek(to: newValue)
                        }
                    ),
                    range: 0...player.getActualDuration(for: episode),
                    iconType: .pauseOnly,
                    progressColor: displayedInQueue ? .black : foregroundColor,
                    lineWidth: progressLineWidth
                )
            } else if episodePlayed && !displayedInQueue {
                // Show restart icon when episode has been played
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17))
                    .foregroundColor(displayedInQueue ? .black : foregroundColor)
            } else {
                // Show circular progress with play icon normally
                PPCircularProgress(
                    value: Binding(
                        get: { playbackPosition },
                        set: { newValue in
                            playbackPosition = newValue
                            player.seek(to: newValue)
                        }
                    ),
                    range: 0...player.getActualDuration(for: episode),
                    iconType: .playOnly,
                    progressColor: displayedInQueue ? .black : foregroundColor,
                    lineWidth: progressLineWidth
                )
            }
        }
        .frame(width: buttonSize, height: buttonSize)
        .onAppear {
            // Initialize state from player/episode on appear
            isPlaying = player.isPlayingEpisode(episode)
            isLoading = player.isLoadingEpisode(episode)
            playbackPosition = player.getProgress(for: episode)
            episodePlayed = episode.isPlayed
            
            // Do background tasks if needed
            Task.detached(priority: .background) {
                await player.writeActualDuration(for: episode)
            }
        }
        // Listen for player state changes (play/pause)
        .onChange(of: player.state) { newState in
            withAnimation(.easeInOut(duration: 0.3)) {
                // Update local state based on player state
                isPlaying = player.isPlayingEpisode(episode)
                isLoading = player.isLoadingEpisode(episode)
                
                // Only update if this is the current episode
                if let id = episode.id,
                   let currentId = newState.currentEpisodeID,
                   id == currentId {
                    playbackPosition = player.getProgress(for: episode)
                }
            }
        }
        // Add a timer to continuously update the progress
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            // Only update if this episode is playing
            if player.isPlayingEpisode(episode) {
                playbackPosition = player.getProgress(for: episode)
            }
        }
        // Track changes to episode.isPlayed
        .onChange(of: episode.isPlayed) { newValue in
            episodePlayed = newValue
            
            // If marked as played, reset progress display
            if newValue {
                playbackPosition = 0
            }
        }
    }
}
