//
//  PeapodAppApp.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI

@main
struct PeapodAppApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var toastManager = ToastManager()
    @StateObject private var syncMonitor: CloudSyncMonitor
    
    init() {
        CloudKitMigrator.migrateSubscribedContentIfNeeded(context: persistenceController.container.viewContext)
        let container = persistenceController.container
        _syncMonitor = StateObject(wrappedValue: CloudSyncMonitor(container: container))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(toastManager)
                .environmentObject(syncMonitor)
        }
    }
}
