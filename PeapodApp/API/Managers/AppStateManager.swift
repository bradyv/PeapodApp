//
//  AppStateManager.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-03.
//

import SwiftUI

class AppStateManager: ObservableObject {
    enum AppState {
        case onboarding
        case main
    }
    
    enum OnboardingStep {
        case welcome
        case importOPML
        case selectPodcasts
        case requestNotifications
    }
    
    @AppStorage("showOnboarding") private var showOnboarding: Bool = true
    @Published var currentOnboardingStep: OnboardingStep = .welcome
    
    // Initialize with the correct state immediately
    @Published var currentState: AppState
    
    init() {
        let shouldShowOnboarding = UserDefaults.standard.object(forKey: "showOnboarding") as? Bool ?? true
        currentState = shouldShowOnboarding ? .onboarding : .main
    }
    
    func beginOnboarding() {
        withAnimation(.easeInOut(duration: 0.6)) {
            self.currentOnboardingStep = .selectPodcasts
        }
    }
    
    func importPodcasts() {
        withAnimation(.easeInOut(duration: 0.6)) {
            self.currentOnboardingStep = .importOPML
        }
    }
    
    func completeOnboarding() {
        // Check if user has subscribed to any podcasts
        let context = PersistenceController.shared.container.viewContext
        let subscribedCount = (try? Podcast.totalSubscribedCount(in: context)) ?? 0
        showOnboarding = false
        
        if subscribedCount > 0 {
            currentOnboardingStep = .requestNotifications
        } else {
            currentState = .main
        }
        
        EpisodeRefresher.refreshAllSubscribedPodcasts(context: context)
    }
    
    func completeNotificationRequest() {
        currentState = .main
    }
}
