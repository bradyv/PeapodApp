//
//  AppStateManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-03.
//

import SwiftUI
import CoreData
import CloudKit

class AppStateManager: ObservableObject {
    enum AppState {
        case splash
        case onboarding
        case returningUser
        case requestNotifications
        case main
    }
    
    @Published var currentState: AppState = .splash
    @AppStorage("showOnboarding") private var showOnboarding: Bool = true
    @Published var hasCloudKitAccount: Bool = false
    
    func startSplashSequence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.6)) {
                self.currentState = self.showOnboarding ? .onboarding : .main
            }
        }
    }
    
    func checkForReturningUser() {
        let container = CKContainer.default()
        
        container.accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("🔵 CloudKit account available")
                    self.hasCloudKitAccount = true
                    
                    // Always show returning user view if they have a CloudKit account
                    // Let them decide whether to restore or start fresh
                    self.currentState = .returningUser
                    
                case .noAccount, .restricted, .couldNotDetermine:
                    print("🔴 CloudKit account not available: \(status)")
                    self.hasCloudKitAccount = false
                    self.currentState = .onboarding
                    
                case .temporarilyUnavailable:
                    print("🔴 CloudKit account temporarily unavailable: \(status)")
                    self.hasCloudKitAccount = false
                    self.currentState = .onboarding
                    
                @unknown default:
                    print("🟡 Unknown CloudKit status")
                    self.hasCloudKitAccount = false
                    self.currentState = .onboarding
                }
            }
        }
    }
    
    func checkForExistingData() -> Bool {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("Error checking for existing data: \(error)")
            return false
        }
    }
    
    func startSplashSequence(withCloudKitCheck: Bool = false) {
        currentState = .splash
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if withCloudKitCheck {
                self.checkForReturningUser()
            } else {
                // Skip to onboarding or main based on existing logic
                if !self.showOnboarding {
                    self.currentState = .main
                } else {
                    self.currentState = .onboarding
                }
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
