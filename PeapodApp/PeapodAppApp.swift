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
    @StateObject private var fetcher = PodcastFetcher()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fetcher)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
