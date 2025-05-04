//
//  AppStateManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-03.
//

import SwiftUI

class AppStateManager: ObservableObject {
    enum AppState {
        case splash
        case onboarding
        case main
    }
    
    @Published var currentState: AppState = .splash
    @AppStorage("showOnboarding") private var showOnboarding: Bool = true
    
    func startSplashSequence() {
        // Show splash screen for 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.6)) {
                // Go directly to main content or onboarding based on user status
                self.currentState = self.showOnboarding ? .onboarding : .main
            }
        }
    }
    
    func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.6)) {
            showOnboarding = false
            currentState = .main
        }
    }
}
