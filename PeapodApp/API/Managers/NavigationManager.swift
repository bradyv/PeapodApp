//
//  NavigationManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-09-12.
//

import SwiftUI

class NavigationManager: ObservableObject {
    @Published var episodePath = NavigationPath()
    
    func navigateToEpisode(_ episode: Episode) {
        episodePath.append(episode)
    }
    
    func clearPath() {
        episodePath = NavigationPath()
    }
}
