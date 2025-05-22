//
//  NotificationManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-28.
//

import UserNotifications
import UIKit

func sendNewEpisodeNotification(for episode: Episode) {
    guard let title = episode.podcast?.title else { return }
    guard let subtitle = episode.title else { return }

    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = subtitle
    content.body = parseHtml(episode.episodeDescription ?? "New episode available!")
    content.sound = .default
    content.userInfo = ["episodeID": episode.id ?? ""]

    // If artwork exists, try to attach it
    if let imageUrlString = episode.podcast?.image,
       let imageUrl = URL(string: imageUrlString) {
        
        // Download the image asynchronously
        URLSession.shared.downloadTask(with: imageUrl) { tempFileUrl, response, error in
            if let tempFileUrl = tempFileUrl {
                do {
                    let ext = imageUrl.pathExtension.isEmpty ? "jpg" : imageUrl.pathExtension
                    let uniqueName = UUID().uuidString + "." + ext
                    let localUrl = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName)

                    try FileManager.default.moveItem(at: tempFileUrl, to: localUrl)

                    let attachment = try UNNotificationAttachment(identifier: "episodeImage", url: localUrl)
                    content.attachments = [attachment]
                } catch {
                    print("❌ Failed to attach image to notification: \(error.localizedDescription)")
                }
            } else {
                print("❌ Image download failed: \(error?.localizedDescription ?? "Unknown error")")
            }

            // Whether download succeeds or fails, always send notification
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
        }.resume()
        
    } else {
        // No artwork, send notification immediately
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
}

private func downloadImageAndAttach(from url: URL, content: UNMutableNotificationContent, completion: @escaping (UNNotificationRequest) -> Void) {
    let task = URLSession.shared.downloadTask(with: url) { tempFileUrl, response, error in
        guard let tempFileUrl = tempFileUrl else {
            completion(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return
        }

        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let uniqueName = UUID().uuidString + "." + ext
        let localUrl = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName)

        do {
            try FileManager.default.moveItem(at: tempFileUrl, to: localUrl)

            let attachment = try UNNotificationAttachment(identifier: "episodeImage", url: localUrl)
            content.attachments = [attachment]
        } catch {
            print("❌ Could not attach image to notification: \(error.localizedDescription)")
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        completion(request)
    }
    task.resume()
}
