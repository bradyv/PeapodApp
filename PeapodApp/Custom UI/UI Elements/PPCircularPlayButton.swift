//
//  PPCircularProgress.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-15.
//

import SwiftUI

struct PPCircularPlayButton: View {
    @EnvironmentObject var player: AudioPlayerManager
    let episode: Episode
    let displayedInQueue: Bool
    let buttonSize: CGFloat
    let full: Double = 1.0
    
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
    
    var body: some View {
        
        Image(systemName: isPlaying ? "pause.circle" : "play.circle", variableValue: progress > 0 && duration > 0 || isPlaying ? progress / duration : full)
            .symbolVariableValueMode(.draw)
            .foregroundStyle(displayedInQueue ? Color.white : Color.heading)
            .contentTransition(.symbolEffect(.replace))
    }
}
