//
//  RequestNotificationsView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-30.
//

import SwiftUI
import UserNotifications

struct RequestNotificationsView: View {
    let onComplete: () -> Void
    var namespace: Namespace.ID
    
    var body: some View {
        VStack {
            Spacer()
            
            Text("Want to be notified about new episodes?")
                .titleSerif()
            
            Button(action: {
                requestNotificationPermission()
            }) {
                Text("Notify Me")
                    .frame(maxWidth:.infinity)
            }
            .buttonStyle(
                PPButton(
                    type: .filled,
                    colorStyle: .monochrome,
                    customColors: ButtonCustomColors(foreground: Color.background, background: Color.heading)
                )
            )
            
            Button(action: {
                skipNotifications()
            }) {
                Text("Maybe Later")
                    .frame(maxWidth:.infinity)
            }
            .buttonStyle(
                PPButton(
                    type:.transparent,
                    colorStyle:.monochrome
                )
            )
        }
        .padding()
        .background(
            Image("notifications")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
        .background(Color.background)
        .frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    // Enable notifications in app when system permission granted
                    UserDefaults.standard.set(true, forKey: "appNotificationsEnabled")
                    UIApplication.shared.registerForRemoteNotifications()
                    LogManager.shared.info("✅ Notifications enabled")
                } else {
                    LogManager.shared.error("❌ Notifications denied")
                }
                onComplete()
            }
        }
    }
    
    private func skipNotifications() {
        onComplete()
    }
}
