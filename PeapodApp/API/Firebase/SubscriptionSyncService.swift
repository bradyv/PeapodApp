//
//  SubscriptionSyncService.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-24.
//

import Foundation
import CoreData
import FirebaseMessaging
import FirebaseFunctions
import UIKit

class SubscriptionSyncService {
    static let shared = SubscriptionSyncService()
    private init() {}
    
    func syncSubscriptionsWithBackend() {
        guard let fcmToken = Messaging.messaging().fcmToken else {
            print("❌ No FCM token available")
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        
        do {
            let subscribedPodcasts = try context.fetch(request)
            let feedUrls = subscribedPodcasts.compactMap { $0.feedUrl }
            
            let cleanUserID = getUserID()
            
            // Use Firebase Functions SDK
            let functions = Functions.functions()
            let updateSubscriptions = functions.httpsCallable("updateSubscriptions")
            
            let data: [String: Any] = [
                "fcmToken": fcmToken,
                "userID": cleanUserID,
                "subscribedFeeds": feedUrls,
                "environment": getCurrentEnvironment()
            ]
            
            updateSubscriptions.call(data) { result, error in
                if let error = error {
                    print("❌ Failed to sync subscriptions with Firebase Functions: \(error)")
                } else {
                    print("✅ Subscriptions synced successfully with Firebase Functions")
                }
            }
            
        } catch {
            print("❌ Failed to fetch subscribed podcasts: \(error)")
        }
    }
    
    private func getCurrentEnvironment() -> String {
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
    
    private func getUserID() -> String {
        // Use device identifier or generate a new UUID
        // This is much simpler and guaranteed to work with Firestore
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
}
