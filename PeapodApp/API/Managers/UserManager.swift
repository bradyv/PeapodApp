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
    
    private init() {
        setupUserObservation()
        loadCurrentUser()
    }
    
    // MARK: - Core Data Observation
    
    private func setupUserObservation() {
        // Listen for Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)
            .sink { [weak self] _ in
                self?.loadCurrentUser()
            }
            .store(in: &cancellables)
    }
    
    private func loadCurrentUser() {
        // Ensure Core Data operations happen on the context's queue
        context.perform { [weak self] in
            guard let self = self else { return }
            
            let request: NSFetchRequest<User> = User.fetchRequest()
            request.fetchLimit = 1
            
            do {
                let user = try self.context.fetch(request).first
                DispatchQueue.main.async {
                    self.currentUser = user
                }
            } catch {
                print("❌ UserManager: Failed to fetch current user: \(error)")
                DispatchQueue.main.async {
                    self.currentUser = nil
                }
            }
        }
    }
    
    // MARK: - Public API
    
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
//        return userType == .subscriber
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
    
    /// The relevant date for display purposes (purchase date for subscribers, user since for others)
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
    
    // MARK: - User Management
    
    /// Creates a new user if none exists, or returns the existing user
    @discardableResult
    func setupCurrentUser() -> User? {
        if let existingUser = currentUser {
            // Ensure userSince is set if it's nil
            if existingUser.userSince == nil {
                existingUser.userSince = Date()
                saveContext()
            }
            return existingUser
        } else {
            return createNewUser()
        }
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
        
        saveContext()
        loadCurrentUser() // Refresh the cached user
        
        print("✅ UserManager: Created new user with type: \(newUser.memberType?.rawValue ?? "unknown")")
        return newUser
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
        
        saveContext()
        print("✅ UserManager: Updated member type from \(oldType?.rawValue ?? "nil") to \(newType.rawValue)")
    }
    
    /// Sets the user's purchase date (typically called when completing a purchase)
    func setPurchaseDate(_ date: Date = Date()) {
        guard let user = currentUser else {
            print("❌ UserManager: No current user to update")
            return
        }
        
        user.purchaseDate = date
        saveContext()
        print("✅ UserManager: Set purchase date to \(date)")
    }
    
    /// Clears the user's purchase date (typically called when subscription expires)
    func clearPurchaseDate() {
        guard let user = currentUser else {
            print("❌ UserManager: No current user to update")
            return
        }
        
        user.purchaseDate = nil
        saveContext()
        print("✅ UserManager: Cleared purchase date")
    }
    
    // MARK: - Helper Methods
    
    private func saveContext() {
        context.perform { [weak self] in
            guard let self = self else { return }
            
            if self.context.hasChanges {
                do {
                    try self.context.save()
                } catch {
                    print("❌ UserManager: Failed to save context: \(error)")
                }
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
