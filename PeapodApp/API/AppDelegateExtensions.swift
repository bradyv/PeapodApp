//
//  AppDelegateExtensions.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-19.
//

import Foundation
import UIKit
import CoreData
import UserNotifications
import BackgroundTasks

// MARK: - App Delegate Extensions

extension AppDelegate {
    
    // MARK: - Setup Methods
    
    /// Setup everything needed at app launch
    func setupApp(context: NSManagedObjectContext) {
        // Setup user
        setupCurrentUser(context: context)
        
        // Register background tasks
        registerBackgroundTasks()
        
        // Request notification permissions
        requestNotificationPermissions()
    }
    
    /// Register background tasks
    private func registerBackgroundTasks() {
        // Let PodcastManager handle this now
        PodcastManager.shared.scheduleEpisodeRefresh()
        PodcastManager.shared.scheduleEpisodeCleanup()
    }
    
    /// Request notification permissions
    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        print("✅ Local notifications authorized")
                    } else if let error = error {
                        print("❌ Notification permission error: \(error.localizedDescription)")
                    } else {
                        print("❌ Notification permission denied")
                    }
                }
            }
        }
    }
    
    /// Setup the current user
    func setupCurrentUser(context: NSManagedObjectContext) {
        let request: NSFetchRequest<User> = User.fetchRequest()
        
        do {
            let users = try context.fetch(request)
            
            if let existingUser = users.first {
                checkAndSetUserSince(for: existingUser, context: context)
            } else {
                let newUser = User(context: context)
                newUser.userSince = Date()
                
                // Use the computed property from the extension
                if let receiptURL = Bundle.main.appStoreReceiptURL {
                    let isDownloadedFromTestFlight = receiptURL.lastPathComponent == "sandboxReceipt"
                    // Use the value of isDownloadedFromTestFlight to determine if the app is running through TestFlight Beta
                    
                    if isDownloadedFromTestFlight {
                        newUser.memberType = .betaTester
                    } else {
                        newUser.memberType = .listener
                    }
                }
                
                try context.save()
                print("New user created with userSince: \(newUser.userSince!)")
            }
        } catch {
            print("Failed to fetch or create user: \(error)")
        }
    }
    
    func checkAndSetUserSince(for user: User, context: NSManagedObjectContext) {
        // Check if userSince is nil
        if user.userSince == nil {
            // Set to current date
            user.userSince = Date()
            
            // Save the context
            do {
                try context.save()
                print("User since date set to: \(user.userSince!)")
            } catch {
                print("Failed to save user since date: \(error)")
            }
        }
    }
    
    // MARK: - Notification Handling
    
    func handleNotificationTap(with episodeID: String) {
        // Store the episode ID for cold start scenarios
        AppDelegate.pendingNotificationEpisodeID = episodeID
        
        // Also post notification for immediate handling if app is already running
        NotificationCenter.default.post(name: .didTapEpisodeNotification, object: episodeID)
    }
    
    // MARK: - Debug Methods
    
    func debugPurgeOldEpisodes() {
        // Forward to PodcastManager
        PodcastManager.shared.debugPurgeOldEpisodes()
    }
}
