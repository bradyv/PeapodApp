//
//  PPCircularProgress.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-15.
//

import SwiftUI

struct PPCircularPlayButton: View {
    @EnvironmentObject var player: AudioPlayerManager
    let episode: Episode
    let displayedInQueue: Bool
    let buttonSize: CGFloat
    
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
//        let replay = episode.isPlayed && !displayedInQueue && !isLoading
//        if replay {
//            Image(systemName: "arrow.clockwise")
//                .font(.system(size: buttonSize * 0.8, weight: .medium))
//                .frame(width: buttonSize, height: buttonSize)
//            
//        } else {
            ZStack {
                // Background circle
                Circle()
                    .stroke(
                        displayedInQueue ? Color.black : Color.heading,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .opacity(0.3)
                    .frame(width: buttonSize, height: buttonSize)
                
                // Progress ring (if episode has been started)
                if isLoading {
                    PPSpinner(color: displayedInQueue ? Color.black : Color.heading)
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                } else if progress > 0 && duration > 0 {
                    Circle()
                        .trim(from: 0, to: progress / duration)
                        .stroke(
                            displayedInQueue ? Color.black : Color.heading,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: buttonSize, height: buttonSize)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
                
                // Play/pause/loading icon
                Group {
                    if isPlaying {
                        Image(systemName: "pause.fill")
                            .font(.system(size: buttonSize * 0.6, weight: .medium))
                            .foregroundColor(displayedInQueue ? Color.black : Color.heading)
                    } else if !isLoading {
                        Image(systemName: "play.fill")
                            .font(.system(size: buttonSize * 0.6, weight: .medium))
                            .foregroundColor(displayedInQueue ? Color.black : Color.heading)
                    }
                }
            }
//        }
    }
}
