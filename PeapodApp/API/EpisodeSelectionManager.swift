//
//  EpisodeSelectionManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-01.
//

import SwiftUI
import Combine

class EpisodeSelectionManager: ObservableObject {
    @Published var selectedEpisode: Episode? = nil
    
    func selectEpisode(_ episode: Episode) {
        selectedEpisode = episode
    }
    
    func clearSelection() {
        selectedEpisode = nil
    }
}
