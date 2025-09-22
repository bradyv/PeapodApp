//
//  UserManager.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-26.
//

import Foundation
import CoreData
import Combine
import UIKit

@MainActor
class UserManager: ObservableObject {
    static let shared = UserManager()
    
    private let context = PersistenceController.shared.container.viewContext
    private var cancellables = Set<AnyCancellable>()
    
    // Published properties for SwiftUI reactivity
    @Published private(set) var currentUser: User?
    
    // Cache keys for UserDefaults
    private let hasCompletedInitialSetupKey = "UserManager.hasCompletedInitialSetup"
    private let lastUserCheckVersionKey = "UserManager.lastUserCheckVersion"
    
    // Version for invalidating cache when user setup logic changes
    private let currentSetupVersion = "1.0"
    
    private init() {
        setupUserObservation()
        setupSubscriptionObservation()
        loadCurrentUser()
    }
    
    // MARK: - Core Data Observation
    
    private func setupUserObservation() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)
            .compactMap { notification -> Notification? in
                let userInfo = notification.userInfo
                let insertedObjects = userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? Set()
                let updatedObjects = userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? Set()
                let deletedObjects = userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? Set()
                
                let allChangedObjects = insertedObjects.union(updatedObjects).union(deletedObjects)
                let hasUserChanges = allChangedObjects.contains { $0 is User }
                
                return hasUserChanges ? notification : nil
            }
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    self.loadCurrentUser()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Subscription Status Observation
    
    private func setupSubscriptionObservation() {
        // Listen for subscription status changes and update Core Data accordingly
        // Since hasPremiumAccess is computed from hasSubscription || hasLifetime,
        // we need to observe both underlying properties
        Publishers.CombineLatest(
            SubscriptionManager.shared.$hasSubscription,
            SubscriptionManager.shared.$hasLifetime
        )
        .map { hasSubscription, hasLifetime in
            return hasSubscription || hasLifetime
        }
        .removeDuplicates()
        .sink { [weak self] hasPremium in
            Task { @MainActor in
                await self?.updateUserTypeForSubscriptionStatus(hasPremium: hasPremium)
            }
        }
        .store(in: &cancellables)
    }
    
    private func updateUserTypeForSubscriptionStatus(hasPremium: Bool) async {
        guard let user = currentUser else { return }
        
        let targetMemberType: MemberType = hasPremium ? .subscriber : .listener
        
        // Only update if the member type actually changed
        if user.memberType != targetMemberType {
            user.memberType = targetMemberType
            
            // Update the legacy userType field for backward compatibility
            user.userType = targetMemberType.rawValue
            
            saveContextSynchronously()
            
            LogManager.shared.info("✅ UserManager: Updated user type to \(targetMemberType.rawValue)")
            
            // Refresh the published property
            self.currentUser = user
        }
    }
    
    private func loadCurrentUser() {
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let user = try context.fetch(request).first
            self.currentUser = user
        } catch {
            LogManager.shared.error("❌ UserManager: Failed to fetch current user: \(error)")
            self.currentUser = nil
        }
    }
    
    // MARK: - Setup Caching Logic
    
    private var hasCompletedInitialSetup: Bool {
        get {
            let hasCompleted = UserDefaults.standard.bool(forKey: hasCompletedInitialSetupKey)
            let lastVersion = UserDefaults.standard.string(forKey: lastUserCheckVersionKey)
            return hasCompleted && lastVersion == currentSetupVersion
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasCompletedInitialSetupKey)
            UserDefaults.standard.set(currentSetupVersion, forKey: lastUserCheckVersionKey)
        }
    }
    
    private func markSetupComplete() {
        hasCompletedInitialSetup = true
        LogManager.shared.info("✅ UserManager: Marked initial setup as complete")
    }
    
    // MARK: - User Management
    
    /// Creates a new user if none exists, or returns the existing user
    @discardableResult
    func setupCurrentUser() -> User? {
        // Fast path: If we've already completed setup and have a user, just return it
        if hasCompletedInitialSetup, let existingUser = currentUser {
            print("ℹ️ UserManager: Using cached user setup")
            return existingUser
        }
        
        print("🔄 UserManager: Performing user setup...")
        
        // Force a fresh load in case currentUser is stale
        loadCurrentUser()
        
        if let existingUser = currentUser {
            // Ensure userSince is set if it's nil (migration case)
            var needsSave = false
            
            if existingUser.userSince == nil {
                existingUser.userSince = Date()
                needsSave = true
                LogManager.shared.info("✅ UserManager: Set userSince for existing user")
            }
            
            // Sync user type with current subscription status
            let currentPremiumStatus = SubscriptionManager.shared.hasPremiumAccess
            let expectedMemberType: MemberType = currentPremiumStatus ? .subscriber : .listener
            
            if existingUser.memberType != expectedMemberType {
                existingUser.memberType = expectedMemberType
                existingUser.userType = expectedMemberType.rawValue
                needsSave = true
                LogManager.shared.info("✅ UserManager: Synced user type to \(expectedMemberType.rawValue)")
            }
            
            if needsSave {
                saveContextSynchronously()
            }
            
            markSetupComplete()
            return existingUser
        } else {
            let newUser = createNewUser()
            markSetupComplete()
            return newUser
        }
    }
    
    /// Force a complete re-setup (useful for testing or when user data might be corrupted)
    func forceResetSetup() {
        print("🔄 UserManager: Forcing setup reset")
        hasCompletedInitialSetup = false
        setupCurrentUser()
    }
    
    /// Creates a new user with default values
    private func createNewUser() -> User? {
        let newUser = User(context: context)
        newUser.userSince = Date()
        
        // All new users start as listeners (preserving your existing logic)
        newUser.memberType = .listener
        newUser.userType = MemberType.listener.rawValue
        
        saveContextSynchronously()
        loadCurrentUser() // Refresh the cached user
        
        LogManager.shared.info("✅ UserManager: Created new user with type: listener")
        return newUser
    }
    
    // MARK: - User Properties
    
    /// When the user first started using the app
    var userSince: Date? {
        return currentUser?.userSince
    }
    
    // MARK: - Subscription Status (delegates to SubscriptionManager)
    
    /// Whether the user has premium access (subscription or lifetime)
    var hasPremiumAccess: Bool {
        return SubscriptionManager.shared.hasPremiumAccess
    }
    
    /// Whether the user has an active subscription
    var hasSubscription: Bool {
        return SubscriptionManager.shared.hasSubscription
    }
    
    /// Whether the user has lifetime access
    var hasLifetime: Bool {
        return SubscriptionManager.shared.hasLifetime
    }
    
    /// When the user purchased their subscription/lifetime
    var purchaseDate: Date? {
        return SubscriptionManager.shared.relevantPurchaseDate
    }
    
    /// Display name for the current member type (now reflects actual Core Data state)
    var memberTypeDisplay: String {
        // Use the actual Core Data member type, which should be synced with subscription status
        switch currentUser?.memberType {
        case .subscriber:
            if hasLifetime {
                return "Lifetime Member"
            } else {
                return "Subscriber"
            }
        case .betaTester:
            return "Beta Tester"
        case .listener, .none:
            return "Listener"
        }
    }
    
    /// The relevant date for display purposes
    var userDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        if hasPremiumAccess, let purchaseDate = purchaseDate {
            return formatter.string(from: purchaseDate)
        } else if let userSince = userSince {
            return formatter.string(from: userSince)
        } else {
            return "Unknown"
        }
    }
    
    /// Formatted string for "Since" display
    var formattedUserSince: String {
        guard let date = userSince else { return "Unknown" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Formatted string for purchase date display
    var formattedPurchaseDate: String {
        guard let date = purchaseDate else { return "No Purchase" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    // MARK: - Legacy Properties (for compatibility)
    
    /// The current user's member type from Core Data
    var userType: MemberType? {
        guard let user = currentUser,
              let typeRaw = user.userType,
              let type = MemberType(rawValue: typeRaw) else {
            return .listener // Default to listener
        }
        return type
    }
    
    /// Whether the user is a listener (now based on Core Data, synced with subscription)
    var isListener: Bool {
        return currentUser?.memberType == .listener
    }
    
    /// Whether the user is a subscriber (now based on Core Data, synced with subscription)
    var isSubscriber: Bool {
        return currentUser?.memberType == .subscriber
    }
    
    // MARK: - Manual Sync Method
    
    /// Force sync user type with current subscription status
    func syncWithSubscriptionStatus() async {
        let hasPremium = SubscriptionManager.shared.hasPremiumAccess
        await updateUserTypeForSubscriptionStatus(hasPremium: hasPremium)
    }
    
    // MARK: - Helper Methods
    
    private func saveContextSynchronously() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                LogManager.shared.error("❌ UserManager: Failed to save context: \(error)")
            }
        }
    }
}

// MARK: - Convenience Extensions

extension UserManager {
    /// Returns the clean user ID for external services (like Firebase)
    var cleanUserID: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    /// Returns the current environment string
    var currentEnvironment: String {
        guard let bundleId = Bundle.main.bundleIdentifier else { return "unknown" }
        
        switch bundleId {
        case "fm.peapod.debug":
            return "debug"
        case "fm.peapod":
            return "prod"
        default:
            return "prod"
        }
    }
}
