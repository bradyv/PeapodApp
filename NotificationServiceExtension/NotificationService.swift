//
//  NotificationService.swift
//  NotificationServiceExtension
//
//  Created by Brady Valentino on 2025-05-24.
//

import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestAttemptContent = bestAttemptContent {
            // Check for image URL in the payload
            if let imageURLString = bestAttemptContent.userInfo["fcm_options"] as? [String: Any],
               let imageURL = imageURLString["image"] as? String,
               let url = URL(string: imageURL) {
                
                downloadImage(from: url) { attachment in
                    if let attachment = attachment {
                        bestAttemptContent.attachments = [attachment]
                    }
                    contentHandler(bestAttemptContent)
                }
            } else {
                contentHandler(bestAttemptContent)
            }
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
    
    private func downloadImage(from url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        URLSession.shared.downloadTask(with: url) { (location, response, error) in
            guard let location = location else {
                completion(nil)
                return
            }
            
            let tmpDirectory = NSTemporaryDirectory()
            let tmpFile = "image_\(UUID().uuidString)"
            let tmpURL = URL(fileURLWithPath: tmpDirectory).appendingPathComponent(tmpFile)
            
            do {
                try FileManager.default.moveItem(at: location, to: tmpURL)
                let attachment = try UNNotificationAttachment(identifier: "image", url: tmpURL, options: nil)
                completion(attachment)
            } catch {
                completion(nil)
            }
        }.resume()
    }
}
