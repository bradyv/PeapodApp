//
//  AppDelegate.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-24.
//

import UIKit
import BackgroundTasks
import CoreData
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // Static property to store pending notification episode ID
    static var pendingNotificationEpisodeID: String?
    
    override init() {
        super.init()
        print("🧬 AppDelegate initialized")
        UNUserNotificationCenter.current().delegate = self
    }
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Initialize Core Data stack
        let context = PersistenceController.shared.container.viewContext
        
        // Setup app components
        setupApp(context: context)
        
        // Schedule first podcast refresh
        PodcastManager.shared.scheduleEpisodeRefresh()
        
        // Log pending background tasks
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                for request in requests {
                    print("📋 Pending BGTask:", request.identifier)
                }
            }
        }
        
        return true
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let episodeID = userInfo["episodeID"] as? String {
            handleNotificationTap(with: episodeID)
        }
        completionHandler()
    }
}
