//
//  NotificationService.swift
//  NotificationServiceExtension
//
//  Created by Brady Valentino on 2025-05-24.
//

import UserNotifications
import FirebaseCore
import FirebaseMessaging

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        
        // Configure Firebase if not already configured
        if FirebaseApp.app() == nil {
            FirebaseConfig.configure()
        }
        
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }
        
        // Log the notification payload for debugging
        print("🔔 Notification received in extension")
        print("📦 Payload: \(bestAttemptContent.userInfo)")
        
        // Let Firebase handle the image attachment automatically
        Messaging.messaging().appDidReceiveMessage(bestAttemptContent.userInfo)
        
        // Use Firebase's extension helper to populate notification content with image
        Messaging.serviceExtension().populateNotificationContent(
            bestAttemptContent,
            withContentHandler: contentHandler
        )
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
