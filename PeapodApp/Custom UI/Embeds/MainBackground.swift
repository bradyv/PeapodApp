//
//  MainBackground.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-31.
//

import SwiftUI
import Kingfisher

struct MainBackground: View {
    @Environment(\.managedObjectContext) private var context
    @State private var displayedEpisode: Episode?
    @State private var currentScrollIndex: Int = 0
    @State private var queue: [Episode] = []
    
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
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            // Refresh queue when Core Data changes
            loadQueue()
        }
        .onAppear {
            loadQueue()
        }
        .offset(y:-200)
    }
    
    private func loadQueue() {
        queue = fetchEpisodesInPlaylist(named: "Queue", context: context)
        updateDisplayedEpisode()
    }
    
    private func updateDisplayedEpisode() {
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
