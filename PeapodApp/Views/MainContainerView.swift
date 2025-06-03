//
//  MainContainerView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-03.
//

import SwiftUI

struct MainContainerView: View {
    @EnvironmentObject var appStateManager: AppStateManager
    @EnvironmentObject var nowPlayingManager: NowPlayingVisibilityManager
    @EnvironmentObject var toastManager: ToastManager
    @Environment(\.managedObjectContext) private var context
    @Namespace var namespace
    
    var body: some View {
        ZStack {
            // Layer 1: Main content (always initialized but conditionally visible)
            ContentView(namespace: namespace)
                .opacity(appStateManager.currentState == .main ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: appStateManager.currentState)
            
            // Layer 2: Onboarding (conditionally visible)
            if appStateManager.currentState == .onboarding {
                WelcomeView(
                    completeOnboarding: {
                        appStateManager.completeOnboarding()
                    },
                    namespace: namespace
                )
                .transition(.opacity)
            }
            
            // Layer 3: Request Notifications (conditionally visible)
            if appStateManager.currentState == .requestNotifications {
                RequestNotificationsView(
                    onComplete: {
                        appStateManager.completeNotificationRequest()
                    },
                    namespace: namespace
                )
                .transition(.opacity)
            }
            
            // Layer 3.5: Returning User (conditionally visible)
            if appStateManager.currentState == .returningUser {
                ReturningUserView(
                    onContinue: {
                        // Set the flag so this flow doesn't show again
                        UserDefaults.standard.set(true, forKey: "hasSeenReturningUserFlow")
                        appStateManager.currentState = .main
                    },
                    namespace: namespace
                )
                .transition(.opacity)
            }
            
            // Layer 4: Splash (conditionally visible on top)
            if appStateManager.currentState == .splash {
                SplashView()
                    .transition(.opacity)
            }
        }
    }
}
