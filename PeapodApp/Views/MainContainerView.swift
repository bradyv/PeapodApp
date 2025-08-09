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
    @State private var runTest: Bool = true
    @AppStorage("showOnboarding") private var showOnboarding: Bool = true
    
    var body: some View {
//        if runTest {
//            Button(action: {
//                runTest.toggle()
//            }) {
//                Label("Show content", systemImage: "chevron.right")
//            }
//            .buttonStyle(.glassProminent)
//        } else {
//            ContentView()
//        }
        
//        ContentView()
//            .fullScreenCover(isPresented: $showOnboarding) {
//                WelcomeView(
//                    completeOnboarding: {
//                        appStateManager.completeOnboarding()
//                    }
//                )
//                .transition(.opacity)
//            }
        
        NewWelcomeView(
            completeOnboarding: {
                appStateManager.completeOnboarding()
            }
        )
        .transition(.opacity)
        
//        switch appStateManager.currentState {
//            case .splash:
//                SplashView()
//                    
//            case .onboarding:
//                WelcomeView(
//                    completeOnboarding: {
//                        appStateManager.completeOnboarding()
//                    }
//                )
//            
//            case .requestNotifications:
//                RequestNotificationsView(
//                    onComplete: {
//                        appStateManager.completeNotificationRequest()
//                    }
//                )
//            
//            case .main:
//                ContentView()
//        }
        
//        ZStack {
//            // Layer 1: Main content (always initialized but conditionally visible)
//            if appStateManager.currentState == .main {
//                ContentView()
//                    .transition(.opacity)
//            }
//            
//            // Layer 2: Onboarding (conditionally visible)
//            if appStateManager.currentState == .onboarding {
//                WelcomeView(
//                    completeOnboarding: {
//                        appStateManager.completeOnboarding()
//                    }
//                )
//                .transition(.opacity)
//            }
//            
//            // Layer 3: Request Notifications (conditionally visible)
//            if appStateManager.currentState == .requestNotifications {
//                RequestNotificationsView(
//                    onComplete: {
//                        appStateManager.completeNotificationRequest()
//                    }
//                )
//                .transition(.opacity)
//            }
//            
//            // Layer 4: Splash (conditionally visible on top)
//            if appStateManager.currentState == .splash {
//                SplashView()
//                    .transition(.opacity)
//            }
//        }
    }
}
