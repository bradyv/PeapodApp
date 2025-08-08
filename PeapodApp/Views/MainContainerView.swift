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
    @State private var runTest: Bool = true
    
    var body: some View {
//        if runTest {
//            Button(action: {
//                runTest.toggle()
//            }) {
//                Label("Show content", systemImage: "chevron.right")
//            }
//            .buttonStyle(.glassProminent)
//        } else {
//            ContentView(namespace:namespace)
//        }
        
        ContentView(namespace:namespace)
//            .fullScreenCover(isPresented: $runTest) {
//                WelcomeView(
//                    completeOnboarding: {
//                        appStateManager.completeOnboarding()
//                    },
//                    namespace: namespace
//                )
//                .transition(.opacity)
//            }
        
//        ContentView(namespace: namespace)
//            .fullScreenCover(isPresented: $runTest) {
//                WelcomeView(
//                    completeOnboarding: {
//                        runTest.toggle()
//                    },
//                    namespace: namespace
//                )
//            }
        
//        ZStack {
//            // Layer 1: Main content (always initialized but conditionally visible)
//            if appStateManager.currentState == .main {
//                ContentView(namespace: namespace)
//                    .transition(.opacity)
//            }
//            
//            // Layer 2: Onboarding (conditionally visible)
//            if appStateManager.currentState == .onboarding {
//                WelcomeView(
//                    completeOnboarding: {
//                        appStateManager.completeOnboarding()
//                    },
//                    namespace: namespace
//                )
//                .transition(.opacity)
//            }
//            
//            // Layer 3: Request Notifications (conditionally visible)
//            if appStateManager.currentState == .requestNotifications {
//                RequestNotificationsView(
//                    onComplete: {
//                        appStateManager.completeNotificationRequest()
//                    },
//                    namespace: namespace
//                )
//                .transition(.opacity)
//            }
//        }
    }
}
