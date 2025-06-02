//
//  NotificationManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-28.
//

import UserNotifications
import UIKit
import Kingfisher

func shouldSendNotifications() -> Bool {
    return UserDefaults.standard.bool(forKey: "appNotificationsEnabled")
}

func sendNewEpisodeNotification(for episode: Episode) {
    guard shouldSendNotifications() else {
        print("📵 Notifications disabled in app settings")
        return
    }
    
    guard let title = episode.podcast?.title else { return }
    guard let subtitle = episode.title else { return }

    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = subtitle
    content.body = parseHtml(episode.episodeDescription ?? "New episode available!")
    content.sound = .default
    content.userInfo = ["episodeID": episode.id ?? ""]

    // Try to get image from Kingfisher cache first
    if let imageUrlString = episode.podcast?.image,
       let imageUrl = URL(string: imageUrlString) {
        
        KingfisherManager.shared.cache.retrieveImage(forKey: imageUrl.cacheKey) { result in
            switch result {
            case .success(let value):
                if let cachedImage = value.image {
                    sendNotificationWithCachedImage(image: cachedImage, content: content, title: title)
                } else {
                    sendNotificationWithoutImage(content: content, title: title)
                }
            case .failure(let error):
                print("❌ Failed to retrieve cached image: \(error.localizedDescription)")
                sendNotificationWithoutImage(content: content, title: title)
            }
        }
    } else {
        sendNotificationWithoutImage(content: content, title: title)
    }
}

private func sendNotificationWithCachedImage(image: UIImage, content: UNMutableNotificationContent, title: String) {
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
        print("❌ Failed to convert image to JPEG data")
        sendNotificationWithoutImage(content: content, title: title)
        return
    }
    
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("jpg")
    
    do {
        try imageData.write(to: tempURL)
        let attachment = try UNNotificationAttachment(identifier: "episodeImage", url: tempURL)
        content.attachments = [attachment]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            // Clean up temp file after notification is scheduled
            try? FileManager.default.removeItem(at: tempURL)
            
            if let error = error {
                print("❌ Failed to schedule notification: \(error.localizedDescription)")
            } else {
                print("✅ Notification sent for \(title) with cached image")
            }
        }
    } catch {
        print("❌ Failed to create image attachment: \(error.localizedDescription)")
        // Clean up temp file on error
        try? FileManager.default.removeItem(at: tempURL)
        sendNotificationWithoutImage(content: content, title: title)
    }
}

private func sendNotificationWithoutImage(content: UNMutableNotificationContent, title: String) {
    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
    )
    
    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("❌ Failed to schedule notification: \(error.localizedDescription)")
        } else {
            print("✅ Notification sent for \(title)")
        }
    }
}

extension Notification.Name {
    static let didTapEpisodeNotification = Notification.Name("didTapEpisodeNotification")
}
