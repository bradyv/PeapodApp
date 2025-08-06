//
//  MainBackground.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-31.
//

import SwiftUI
import Kingfisher

struct MainBackground: View {
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @EnvironmentObject var player: AudioPlayerManager
    @State private var displayedEpisode: Episode?
    @State private var currentScrollIndex: Int = 0
    
    var body: some View {
        ZStack {
            if let episode = displayedEpisode {
                SplashImage(image: episode.episodeImage ?? episode.podcast?.image ?? "")
                    .transition(.opacity)
                    .id(episode.id)
                    .animation(.easeInOut(duration: 0.3), value: episode.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .queueScrollPositionChanged)) { notification in
            if let scrollIndex = notification.object as? Int {
                currentScrollIndex = scrollIndex
                updateDisplayedEpisode()
            }
        }
        .onChange(of: episodesViewModel.queue) { _, _ in
            updateDisplayedEpisode()
        }
        .onAppear {
            updateDisplayedEpisode()
        }
    }
    
    private func updateDisplayedEpisode() {
        let queue = episodesViewModel.queue
        
        if queue.isEmpty {
            withAnimation {
                displayedEpisode = nil
            }
        } else {
            let safeIndex = min(max(0, currentScrollIndex), queue.count - 1)
            let newEpisode = queue[safeIndex]
            
            if displayedEpisode?.id != newEpisode.id {
                withAnimation {
                    displayedEpisode = newEpisode
                }
            }
        }
    }
}

struct GradientBackground: View {
    var body: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color.surface, location: 0.00),
                Gradient.Stop(color: Color.background, location: 1.00),
            ],
            center: UnitPoint(x: 0, y: 0)
        )
        .ignoresSafeArea()
    }
}

extension Notification.Name {
    static let queueScrollPositionChanged = Notification.Name("queueScrollPositionChanged")
}
