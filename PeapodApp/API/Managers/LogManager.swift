//
//  LogManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-15.
//

import SwiftUI
import Darwin

class LogManager {
    static let shared = LogManager()
    private var logFileHandle: FileHandle?
    
    // Configuration
    private let maxLogFileSize: Int64 = 5 * 1024 * 1024 // 5MB per file
    private let maxTotalLogSize: Int64 = 20 * 1024 * 1024 // 20MB total
    private let maxLogFiles = 3 // Keep 3 rotated logs
    
    let logFileURL: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("peapod-logs.txt")
    }()

    func startLogging() {
        // Set UTF-8 locale before redirecting
        setlocale(LC_ALL, "en_US.UTF-8")
        
        rotateLogIfNeeded()
        cleanupOldLogs()
        
        freopen(logFileURL.path.cString(using: .utf8), "a+", stderr)
        freopen(logFileURL.path.cString(using: .utf8), "a+", stdout)
        print("🟢 Logging started at \(Date())\n")
    }

    func clearLog() {
        try? FileManager.default.removeItem(at: logFileURL)
        startLogging()
    }

    func getLogFileURL() -> URL {
        return logFileURL
    }
    
    // MARK: - Enhanced Storage Management
    
    func rotateLogIfNeeded() {
        guard let fileSize = getFileSize(at: logFileURL),
              fileSize > maxLogFileSize else { return }
        
        let timestamp = DateFormatter().string(from: Date())
        let rotatedURL = logFileURL
            .deletingPathExtension()
            .appendingPathExtension("backup-\(timestamp)")
            .appendingPathExtension("txt")
        
        do {
            try FileManager.default.moveItem(at: logFileURL, to: rotatedURL)
            print("🔄 Rotated log file: \(rotatedURL.lastPathComponent)")
        } catch {
            print("❌ Failed to rotate log: \(error)")
        }
    }
    
    func cleanupOldLogs() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: []
            )
            
            // Get all log files
            let logFiles = contents.filter { url in
                url.lastPathComponent.hasPrefix("peapod-logs")
            }.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 > date2 // Newest first
            }
            
            // Remove files beyond maxLogFiles limit
            if logFiles.count > maxLogFiles {
                let filesToDelete = Array(logFiles.dropFirst(maxLogFiles))
                for fileURL in filesToDelete {
                    try fileManager.removeItem(at: fileURL)
                    print("🧹 Deleted excess log: \(fileURL.lastPathComponent)")
                }
            }
            
            // Check total size and remove oldest if needed
            let totalSize = logFiles.compactMap { getFileSize(at: $0) }.reduce(0, +)
            if totalSize > maxTotalLogSize {
                // Remove oldest files until under limit
                var currentSize = totalSize
                for fileURL in logFiles.reversed() { // Start with oldest
                    if currentSize <= maxTotalLogSize { break }
                    if let fileSize = getFileSize(at: fileURL) {
                        try fileManager.removeItem(at: fileURL)
                        currentSize -= fileSize
                        print("🧹 Deleted oversized log: \(fileURL.lastPathComponent)")
                    }
                }
            }
            
        } catch {
            print("❌ Failed to cleanup logs: \(error)")
        }
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
    
    // MARK: - User Support Features
    
    func getAllLogFiles() -> [URL] {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: [])
            return contents.filter { $0.lastPathComponent.hasPrefix("peapod-logs") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            return []
        }
    }
    
    func getTotalLogSize() -> String {
        let totalBytes = getAllLogFiles()
            .compactMap { getFileSize(at: $0) }
            .reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    private func getFileSize(at url: URL) -> Int64? {
        return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }
}

// MARK: - App Lifecycle Integration
extension LogManager {
    func setupAppLifecycleLogging() {
        // Call this from your App delegate or main app
        // Rotate logs on app launch
        rotateLogIfNeeded()
        cleanupOldLogs()
        
        // Clean up when app goes to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.cleanupOldLogs()
        }
    }
}
