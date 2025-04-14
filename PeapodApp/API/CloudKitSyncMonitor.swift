//
//  CloudKitSyncMonitor.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-13.
//

import Foundation
import CoreData

class CloudSyncMonitor: ObservableObject {
    @Published var isSyncing = false
    private var syncTimer: Timer?
    private let backgroundContext: NSManagedObjectContext

    init(container: NSPersistentCloudKitContainer) {
        self.backgroundContext = container.newBackgroundContext()
        self.lastToken = HistoryTokenManager.load() // 🧠 Load token on startup

        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📬 NSPersistentStoreRemoteChange fired")
            self?.checkForCloudKitSync()
        }
    }

    private var lastToken: NSPersistentHistoryToken?

    private func checkForCloudKitSync() {
        print("🔍 Checking persistent history for new CloudKit import transactions...")

        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: lastToken)
        request.fetchRequest = NSPersistentHistoryTransaction.fetchRequest

        do {
            let result = try backgroundContext.execute(request) as? NSPersistentHistoryResult
            let transactions = result?.result as? [NSPersistentHistoryTransaction] ?? []

            print("🔢 Found \(transactions.count) new transactions")

            for transaction in transactions {
                let author = transaction.author ?? "nil"
                print("🧾 Author: \(author)")

                let cloudKitImportAuthor = "NSCloudKitMirroringDelegate.import"

                if author == cloudKitImportAuthor,
                   let changes = transaction.changes,
                   changes.contains(where: { change in
                       guard let entity = change.changedObjectID.entity.name else { return false }
                       return ["Podcast", "Episode"].contains(entity)
                   }) {
                    
                    print("🚀 Detected CloudKit sync for Podcast or Episode")

                    // Always reset the timer, regardless of "first" flag
                    startSyncing()

                    // Only flag completion once
                    if !UserDefaults.standard.bool(forKey: "CloudKitSyncCompleted") {
                        print("✅ First CloudKit sync completed")
                        UserDefaults.standard.set(true, forKey: "CloudKitSyncCompleted")
                    }
                }
            }

            // 🧠 Update the last seen token
            if let lastTransaction = transactions.last {
                lastToken = lastTransaction.token
                HistoryTokenManager.save(lastTransaction.token)
            }

        } catch {
            print("⚠️ Failed to fetch persistent history: \(error)")
        }
    }

    private func startSyncing() {
        print("🚀 Detected CloudKit sync via transaction.originator")
        isSyncing = true

        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.isSyncing = false
            print("🛑 Sync ended")
        }
    }
}

final class HistoryTokenManager {
    private static var tokenURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.bradyv.Peapod") else {
            print("⚠️ App Group container URL could not be found.")
            return nil
        }
        return containerURL.appendingPathComponent("historyToken.data")
    }

    static func save(_ token: NSPersistentHistoryToken) {
        guard let tokenURL else {
            print("⚠️ Cannot save history token: tokenURL is nil")
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            try data.write(to: tokenURL)
        } catch {
            print("⚠️ Failed to save history token: \(error)")
        }
    }

    static func load() -> NSPersistentHistoryToken? {
        guard let tokenURL else {
            print("⚠️ Cannot load history token: tokenURL is nil")
            return nil
        }

        do {
            let data = try Data(contentsOf: tokenURL)
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        } catch {
            print("⚠️ Failed to load history token: \(error)")
            return nil
        }
    }
}
