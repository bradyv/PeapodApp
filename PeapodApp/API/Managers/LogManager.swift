//
//  LogManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-15.
//

import Foundation

class LogManager {
    static let shared = LogManager()
    private var logFileHandle: FileHandle?

    let logFileURL: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("peapod-logs.txt")
    }()

    func startLogging() {
        freopen(logFileURL.path.cString(using: .ascii), "a+", stderr)
        freopen(logFileURL.path.cString(using: .ascii), "a+", stdout)
        print("🟢 Logging started at \(Date())\n")
    }

    func clearLog() {
        try? FileManager.default.removeItem(at: logFileURL)
        startLogging()
    }

    func getLogFileURL() -> URL {
        return logFileURL
    }
    
    func cleanOldLogs(olderThan days: Int = 7) {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        let calendar = Calendar.current
        let expirationDate = calendar.date(byAdding: .day, value: -days, to: Date())!

        do {
            let contents = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [])

            for fileURL in contents where fileURL.lastPathComponent.hasPrefix("peapod-logs") {
                if let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modifiedDate = attrs.contentModificationDate,
                   modifiedDate < expirationDate {
                    try fileManager.removeItem(at: fileURL)
                    print("🧹 Deleted old log: \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            print("❌ Failed to clean up old logs: \(error.localizedDescription)")
        }
    }
}
