//
//  UserManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-26.
//

import Foundation
import CoreData
import Combine
import UIKit

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
        loadCurrentUser()
    }
    
    // MARK: - Core Data Observation
    
    private func setupUserObservation() {
        // Listen for Core Data changes, but only refresh if User entities were affected
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)
            .compactMap { notification -> Notification? in
                // Only process if User entities were changed
                let userInfo = notification.userInfo
                let insertedObjects = userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? Set()
                let updatedObjects = userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? Set()
                let deletedObjects = userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? Set()
                
                let allChangedObjects = insertedObjects.union(updatedObjects).union(deletedObjects)
                let hasUserChanges = allChangedObjects.contains { $0 is User }
                
                return hasUserChanges ? notification : nil
            }
            .sink { [weak self] _ in
                // Only reload if we haven't just completed initial setup
                guard let self = self else { return }
                
                // Avoid reloading immediately after we just set up the user
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.loadCurrentUser()
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadCurrentUser() {
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let user = try context.fetch(request).first
            self.currentUser = user
        } catch {
            print("❌ UserManager: Failed to fetch current user: \(error)")
            self.currentUser = nil
        }
    }
    
    // MARK: - Setup Caching Logic
    
    private var hasCompletedInitialSetup: Bool {
        get {
            // Check if we've completed setup AND if it's for the current version
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
        print("✅ UserManager: Marked initial setup as complete")
    }
    
    // MARK: - User Management
    
    /// Creates a new user if none exists, or returns the existing user
    /// Now with caching to avoid unnecessary operations
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
                print("✅ UserManager: Set userSince for existing user")
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
        
        // Determine member type based on TestFlight vs App Store
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            let isDownloadedFromTestFlight = receiptURL.lastPathComponent == "sandboxReceipt"
            newUser.memberType = isDownloadedFromTestFlight ? .betaTester : .listener
        } else {
            newUser.memberType = .listener
        }
        
        saveContextSynchronously()
        loadCurrentUser() // Refresh the cached user
        
        print("✅ UserManager: Created new user with type: \(newUser.memberType?.rawValue ?? "unknown")")
        return newUser
    }
    
    // MARK: - Rest of your existing methods...
    
    /// The current user's member type
    var userType: MemberType? {
        guard let user = currentUser,
              let typeRaw = user.userType,
              let type = MemberType(rawValue: typeRaw) else {
            return nil
        }
        return type
    }
    
    /// Whether the user is a subscriber
    var isSubscriber: Bool {
        return userType == .listener
    }
    
    /// Whether the user is a beta tester
    var isBetaTester: Bool {
        return userType == .betaTester
    }
    
    /// Whether the user is a listener (free tier)
    var isListener: Bool {
        return userType == .listener
    }
    
    /// When the user first started using the app
    var userSince: Date? {
        return currentUser?.userSince
    }
    
    /// When the user purchased their subscription (if applicable)
    var purchaseDate: Date? {
        return currentUser?.purchaseDate
    }
    
    /// The relevant date for display purposes
    var userDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        if isSubscriber, let purchaseDate = purchaseDate {
            return formatter.string(from: purchaseDate)
        } else if let userSince = userSince {
            return formatter.string(from: userSince)
        } else {
            return "Unknown"
        }
    }
    
    /// Display name for the current member type
    var memberTypeDisplay: String {
        guard let type = userType else { return "Unknown" }
        
        switch type {
        case .listener:
            return "Listener"
        case .betaTester:
            return "Beta Tester"
        case .subscriber:
            return "Subscriber"
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
        guard let date = purchaseDate else { return "Unknown" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Updates the user's member type
    func updateMemberType(_ newType: MemberType) {
        guard let user = currentUser else {
            print("❌ UserManager: No current user to update")
            return
        }
        
        let oldType = user.memberType
        user.memberType = newType
        
        // Set purchase date when upgrading to subscriber
        if newType == .subscriber && oldType != .subscriber {
            user.purchaseDate = Date()
        }
        
        saveContextSynchronously()
        print("✅ UserManager: Updated member type from \(oldType?.rawValue ?? "nil") to \(newType.rawValue)")
    }
    
    /// Sets the user's purchase date
    func setPurchaseDate(_ date: Date = Date()) {
        guard let user = currentUser else {
            print("❌ UserManager: No current user to update")
            return
        }
        
        user.purchaseDate = date
        saveContextSynchronously()
        print("✅ UserManager: Set purchase date to \(date)")
    }
    
    /// Clears the user's purchase date
    func clearPurchaseDate() {
        guard let user = currentUser else {
            print("❌ UserManager: No current user to update")
            return
        }
        
        user.purchaseDate = nil
        saveContextSynchronously()
        print("✅ UserManager: Cleared purchase date")
    }
    
    // MARK: - Helper Methods
    
    private func saveContextSynchronously() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("❌ UserManager: Failed to save context: \(error)")
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
        case "com.bradyv.Peapod.Debug":
            return "debug"
        case "com.bradyv.Peapod.Dev":
            return "dev"
        default:
            return "prod"
        }
    }
}
