//
//  SplashView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-23.
//

import SwiftUI
import RiveRuntime

struct SplashView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appStateManager: AppStateManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var riveModel = RiveViewModel(fileName: "peapod")
    @State private var lastRefreshDate = Date.distantPast
    
    var body: some View {
        ZStack {
            Image("launchimage")
                .resizable()
                .aspectRatio(contentMode: .fill)
            
            RiveViewModel(fileName: "peapod").view()
                .frame(width:128,height:111)
        }
        .ignoresSafeArea()
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Clear badge when app becomes active
                UIApplication.shared.applicationIconBadgeNumber = 0
                
                // 🚀 NEW: Only refresh if it's been more than 30 seconds since last refresh
                let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshDate)
                if timeSinceLastRefresh > 30 {
                    LogManager.shared.info("📱 App foregrounding - refreshing (last refresh: \(String(format: "%.1f", timeSinceLastRefresh))s ago)")
                    forceRefreshPodcasts()
                } else {
                    LogManager.shared.info("📱 App foregrounding - skipping refresh (last refresh: \(String(format: "%.1f", timeSinceLastRefresh))s ago)")
                }
            }
        }
        .onChange(of: appStateManager.currentState) { oldState, newState in
            if oldState != .main && newState == .main {
                // Sync subscriptions when app enters main state
                SubscriptionSyncService.shared.syncSubscriptionsWithBackend()
            }
        }
    }
    
    private func forceRefreshPodcasts() {
        refreshPodcasts(source: "auto")
    }
    
    private func refreshPodcasts(source: String) {
        // Update last refresh time immediately to prevent concurrent calls
        lastRefreshDate = Date()
        
        LogManager.shared.info("🔄 Force refreshing all subscribed podcasts (\(source))")
        
        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context) {
            LogManager.shared.info("✨ \(source.capitalized) refreshed feeds at \(Date())")
        }
    }
}

#Preview {
    SplashView()
}
