//
//  AppStateManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-03.
//

import SwiftUI

class AppStateManager: ObservableObject {
    enum AppState {
//        case splash
        case onboarding
        case requestNotifications
        case main
    }
    
    @Published var currentState: AppState = .main
    @AppStorage("showOnboarding") private var showOnboarding: Bool = true
    
    func startSplashSequence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.6)) {
                self.currentState = self.showOnboarding ? .onboarding : .main
            }
        }
    }
    
    func completeOnboarding() {
        showOnboarding = false
        
        // Check if user has subscribed to any podcasts
        let context = PersistenceController.shared.container.viewContext
        let subscribedCount = (try? Podcast.totalSubscribedCount(in: context)) ?? 0
        
        if subscribedCount > 0 {
            // User has subscriptions, ask about notifications
            withAnimation(.easeInOut(duration: 0.6)) {
                currentState = .requestNotifications
            }
        } else {
            // No subscriptions, go straight to main
            withAnimation(.easeInOut(duration: 0.6)) {
                currentState = .main
            }
        }
    }
    
    func completeNotificationRequest() {
        withAnimation(.easeInOut(duration: 0.6)) {
            currentState = .main
        }
    }
}
