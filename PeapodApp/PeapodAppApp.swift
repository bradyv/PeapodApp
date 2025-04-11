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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(toastManager)
        }
    }
}
