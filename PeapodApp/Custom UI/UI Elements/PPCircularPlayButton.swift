//
//  PPCircularProgress.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-15.
//

import SwiftUI

struct PPCircularPlayButton: View {
    let episode: Episode
    let displayedInQueue: Bool
    let buttonSize: CGFloat
    let full: Double = 1.0
    
    // Get player reference directly - not through EnvironmentObject
    private var player: AudioPlayerManager { AudioPlayerManager.shared }
    
    // Subscribe to time updates for live progress
    @ObservedObject private var timePublisher = AudioPlayerManager.shared.timePublisher
    
    // Computed properties based on unified state
    private var isPlaying: Bool {
        player.isPlayingEpisode(episode)
    }
    
    private var isLoading: Bool {
        player.isLoadingEpisode(episode)
    }
    
    private var progress: Double {
        player.getProgress(for: episode)
    }
    
    private var duration: Double {
        player.getActualDuration(for: episode)
    }
    
    // Calculate the variable value for the SF Symbol
    private var variableValue: Double {
        guard duration > 0 else { return full }
        
        // If this is the currently playing episode, show live progress
        if player.isPlayingEpisode(episode) && progress > 0 {
            return progress / duration
        }
        
        // For non-playing episodes, show saved progress from Core Data
        if progress > 0 {
            return progress / duration
        }
        
        // Default to full circle (unplayed state)
        return full
    }
    
    var body: some View {
        Image(systemName: isPlaying ? "pause.circle" : "play.circle", variableValue: variableValue)
            .symbolVariableValueMode(.draw)
            .foregroundStyle(displayedInQueue ? Color.white : Color.heading)
            .contentTransition(.symbolEffect(.replace))
    }
}
