//
//  PlaybackExtension.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-10-21.
//

import SwiftUI

// Helper methods for the Playback entity
extension Playback {
    
    // Check if episode's download should be auto-deleted (24 hours after being played)
    var shouldAutoDelete: Bool {
        guard isPlayed, let playedDate = playedDate else {
            return false
        }
        
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        return playedDate < twentyFourHoursAgo
    }
}
