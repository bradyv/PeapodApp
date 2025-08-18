//
//  LogManager.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-15.
//

import SwiftUI
import Darwin
import OSLog

class LogManager {
    static let shared = LogManager()
    private var logFileHandle: FileHandle?
    private let queue = DispatchQueue(label: "fm.peapod.logging", qos: .utility)
    private let logger = Logger(subsystem: "fm.peapod.app", category: "LogManager")
    
    // Configuration
    private let maxLogFileSize: Int64 = 1 * 1024 * 1024 // 5MB per file
    private let maxTotalLogSize: Int64 = 5 * 1024 * 1024 // 20MB total
    private let maxLogFiles = 3 // Keep 3 rotated logs
    private let flushInterval: TimeInterval = 2.0 // Force flush every 2 seconds
    
    private var flushTimer: Timer?
    
    let logFileURL: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("peapod-logs.txt")
    }()

    init() {
        setupLogFile()
        setupPeriodicFlush()
        setupConsoleCapture()
    }
    
    deinit {
        flushTimer?.invalidate()
        logFileHandle?.closeFile()
    }

    // MARK: - Enhanced Logging Setup
    
    private func setupLogFile() {
        queue.async {
            self.rotateLogIfNeeded()
            self.cleanupOldLogs()
            
            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: self.logFileURL.path) {
                FileManager.default.createFile(atPath: self.logFileURL.path, contents: nil, attributes: nil)
            }
            
            // Open file handle for writing
            do {
                self.logFileHandle = try FileHandle(forWritingTo: self.logFileURL)
                self.logFileHandle?.seekToEndOfFile()
                self.writeToLog("🟢 Enhanced logging started at \(Date())\n")
            } catch {
                LogManager.shared.error("❌ Failed to open log file: \(error)")
            }
        }
    }
    
    private func setupPeriodicFlush() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in
            self.forceFlush()
        }
    }
    
    private func setupConsoleCapture() {
        // Override print function to capture all console output
        // This is more reliable than freopen
        
        // Store original stderr
        let originalStderr = dup(STDERR_FILENO)
        
        // Create pipe for capturing stderr
        var pipe: [Int32] = [0, 0]
        if Darwin.pipe(&pipe) == 0 {
            // Redirect stderr to our pipe
            dup2(pipe[1], STDERR_FILENO)
            close(pipe[1])
            
            // Read from pipe in background
            DispatchQueue.global(qos: .utility).async {
                let fileHandle = FileHandle(fileDescriptor: pipe[0], closeOnDealloc: true)
                
                while true {
                    let data = fileHandle.availableData
                    if data.isEmpty { break }
                    
                    if let output = String(data: data, encoding: .utf8) {
                        self.writeToLog(output)
                        
                        // Also write to original stderr so we can still see logs in Xcode
                        write(originalStderr, output, output.utf8.count)
                    }
                }
            }
        }
    }
    
    // MARK: - Thread-Safe Logging
    
    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        let formattedMessage = "[\(timestamp)] \(level.emoji) \(message)\n"
        
        writeToLog(formattedMessage)
        
        // Also use OSLog for system integration
        switch level {
        case .debug:
            logger.debug("\(message)")
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        }
    }
    
    private func writeToLog(_ message: String) {
        queue.async {
            guard let data = message.data(using: .utf8),
                  let handle = self.logFileHandle else { return }
            
            handle.write(data)
            
            // Check if we need to rotate after writing
            self.rotateLogIfNeeded()
        }
    }
    
    func forceFlush() {
        queue.async {
            self.logFileHandle?.synchronizeFile()
        }
    }
    
    // MARK: - Public Logging Interface
    
    func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    func info(_ message: String) {
        log(message, level: .info)
    }
    
    func warning(_ message: String) {
        log(message, level: .warning)
    }
    
    func error(_ message: String) {
        log(message, level: .error)
    }
    
    // MARK: - Legacy Support
    
    func startLogging() {
        // Keep for compatibility, but enhanced logging is already started
        log("Legacy startLogging() called", level: .info)
    }

    func clearLog() {
        queue.async {
            self.logFileHandle?.closeFile()
            try? FileManager.default.removeItem(at: self.logFileURL)
            self.setupLogFile()
            self.log("Log cleared by user", level: .info)
        }
    }

    func getLogFileURL() -> URL {
        return logFileURL
    }
    
    // MARK: - Enhanced Storage Management
    
    private func rotateLogIfNeeded() {
        // Must be called on queue
        guard let fileSize = getFileSize(at: logFileURL),
              fileSize > maxLogFileSize else { return }
        
        // Close current handle
        logFileHandle?.closeFile()
        
        // Create timestamped backup
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        let rotatedURL = logFileURL
            .deletingPathExtension()
            .appendingPathExtension("backup-\(timestamp)")
            .appendingPathExtension("txt")
        
        do {
            try FileManager.default.moveItem(at: logFileURL, to: rotatedURL)
            
            // Create new log file and reopen handle
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
            logFileHandle = try FileHandle(forWritingTo: logFileURL)
            
            writeToLog("🔄 Log rotated from \(rotatedURL.lastPathComponent)\n")
        } catch {
            LogManager.shared.error("❌ Failed to rotate log: \(error)")
        }
    }
    
    func cleanupOldLogs() {
        queue.async {
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
                if logFiles.count > self.maxLogFiles {
                    let filesToDelete = Array(logFiles.dropFirst(self.maxLogFiles))
                    for fileURL in filesToDelete {
                        try fileManager.removeItem(at: fileURL)
                        self.writeToLog("🧹 Deleted excess log: \(fileURL.lastPathComponent)\n")
                    }
                }
                
                // Check total size and remove oldest if needed
                let totalSize = logFiles.compactMap { self.getFileSize(at: $0) }.reduce(0, +)
                if totalSize > self.maxTotalLogSize {
                    // Remove oldest files until under limit
                    var currentSize = totalSize
                    for fileURL in logFiles.reversed() { // Start with oldest
                        if currentSize <= self.maxTotalLogSize { break }
                        if let fileSize = self.getFileSize(at: fileURL) {
                            try fileManager.removeItem(at: fileURL)
                            currentSize -= fileSize
                            self.writeToLog("🧹 Deleted oversized log: \(fileURL.lastPathComponent)\n")
                        }
                    }
                }
                
            } catch {
                self.writeToLog("❌ Failed to cleanup logs: \(error)\n")
            }
        }
    }
    
    func cleanOldLogs(olderThan days: Int = 7) {
        queue.async {
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
                        self.writeToLog("🧹 Deleted old log: \(fileURL.lastPathComponent)\n")
                    }
                }
            } catch {
                self.writeToLog("❌ Failed to clean up old logs: \(error.localizedDescription)\n")
            }
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
    
    // MARK: - Log Export for Support
    
    func exportLogsForSupport() -> URL? {
        forceFlush() // Ensure everything is written
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("peapod-support-logs-\(Date().timeIntervalSince1970)")
            .appendingPathExtension("txt")
        
        do {
            var combinedLogs = "Peapod Support Logs\nExported: \(Date())\n"
            combinedLogs += "App Version: \(Bundle.main.releaseVersionNumber ?? "Unknown")\n"
            combinedLogs += "Build: \(Bundle.main.buildVersionNumber ?? "Unknown")\n"
            combinedLogs += "iOS Version: \(UIDevice.current.systemVersion)\n"
            combinedLogs += "Device: \(UIDevice.current.model)\n\n"
            combinedLogs += String(repeating: "=", count: 50) + "\n\n"
            
            for logFile in getAllLogFiles() {
                combinedLogs += "=== \(logFile.lastPathComponent) ===\n"
                if let content = try? String(contentsOf: logFile) {
                    combinedLogs += content
                } else {
                    combinedLogs += "Failed to read file\n"
                }
                combinedLogs += "\n\n"
            }
            
            try combinedLogs.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            writeToLog("❌ Failed to export logs: \(error)")
            return nil
        }
    }
}

// MARK: - Supporting Types

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - App Lifecycle Integration
extension LogManager {
    func setupAppLifecycleLogging() {
        log("Setting up app lifecycle logging", level: .info)
        
        // Clean up when app goes to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.log("App entering background", level: .info)
            self.forceFlush()
            self.cleanupOldLogs()
        }
        
        // Log when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.log("App became active", level: .info)
        }
        
        // Log when app will terminate
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.log("App will terminate", level: .info)
            self.forceFlush()
        }
    }
}

// MARK: - Convenience Functions for Migration
extension LogManager {
    // Replace print statements with these for better logging
    static func print(_ items: Any..., separator: String = " ") {
        let message = items.map { "\($0)" }.joined(separator: separator)
        shared.info(message)
        Swift.print(message) // Also print to console for development
    }
    
    static func debugPrint(_ items: Any..., separator: String = " ") {
        let message = items.map { "\($0)" }.joined(separator: separator)
        shared.debug(message)
        Swift.print(message)
    }
}
