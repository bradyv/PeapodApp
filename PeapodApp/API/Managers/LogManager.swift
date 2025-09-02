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
    
    // MARK: - Thread-Safe Properties
    private var _logFileHandle: FileHandle?
    private let queue = DispatchQueue(label: "fm.peapod.logging", qos: .utility)
    private let logger = Logger(subsystem: "fm.peapod.app", category: "LogManager")
    
    // State management
    private var isSettingUp = false
    private var setupComplete = false
    private let enableConsoleCapture = false // Set to true if you want console capture
    
    // Configuration
    private let maxLogFileSize: Int64 = 1 * 1024 * 1024 // 1MB per file
    private let maxTotalLogSize: Int64 = 5 * 1024 * 1024 // 5MB total
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
        if enableConsoleCapture {
            setupConsoleCapture()
        }
    }
    
    deinit {
        flushTimer?.invalidate()
        _logFileHandle?.closeFile()
    }

    // MARK: - Thread-Safe File Handle Management
    
    private var safeLogFileHandle: FileHandle? {
        // Only return handle if setup is complete and handle is valid
        guard setupComplete, !isSettingUp, let handle = _logFileHandle else { return nil }
        return handle
    }
    
    private func setupLogFile() {
        queue.async {
            self.isSettingUp = true
            defer {
                self.isSettingUp = false
                self.setupComplete = true
            }
            
            self.rotateLogIfNeeded()
            self.cleanupOldLogs()
            
            // Close any existing handle first
            self._logFileHandle?.closeFile()
            self._logFileHandle = nil
            
            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: self.logFileURL.path) {
                FileManager.default.createFile(atPath: self.logFileURL.path, contents: nil, attributes: nil)
            }
            
            // Open file handle for writing with error handling
            do {
                let handle = try FileHandle(forWritingTo: self.logFileURL)
                handle.seekToEndOfFile()
                
                // Only assign if successful
                self._logFileHandle = handle
                self.writeToLogUnsafe("🟢 Enhanced logging started at \(Date())\n")
            } catch {
                // Fallback: try creating the file again
                FileManager.default.createFile(atPath: self.logFileURL.path, contents: nil, attributes: nil)
                do {
                    let handle = try FileHandle(forWritingTo: self.logFileURL)
                    handle.seekToEndOfFile()
                    self._logFileHandle = handle
                    self.writeToLogUnsafe("🟢 Enhanced logging started (after retry) at \(Date())\n")
                } catch {
                    Swift.print("❌ Critical: Failed to open log file after retry: \(error)")
                    // File logging will be disabled, but app continues
                }
            }
        }
    }
    
    private func recreateFileHandle() {
        // Must be called on queue
        guard !isSettingUp else { return }
        
        _logFileHandle?.closeFile()
        _logFileHandle = nil
        
        do {
            let handle = try FileHandle(forWritingTo: logFileURL)
            handle.seekToEndOfFile()
            _logFileHandle = handle
            writeToLogUnsafe("🔄 File handle recreated\n")
        } catch {
            Swift.print("❌ Failed to recreate file handle: \(error)")
        }
    }
    
    private func validateLogState() {
        queue.async {
            // Check if log file exists but handle is nil
            if FileManager.default.fileExists(atPath: self.logFileURL.path) && self._logFileHandle == nil {
                self.recreateFileHandle()
            }
        }
    }
    
    private func setupPeriodicFlush() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in
            self.forceFlush()
        }
    }
    
    private func setupConsoleCapture() {
        // Make console capture optional and more robust
        let originalStderr = dup(STDERR_FILENO)
        guard originalStderr != -1 else {
            Swift.print("❌ Failed to duplicate stderr")
            return
        }
        
        var pipe: [Int32] = [0, 0]
        guard Darwin.pipe(&pipe) == 0 else {
            Swift.print("❌ Failed to create pipe")
            close(originalStderr)
            return
        }
        
        guard dup2(pipe[1], STDERR_FILENO) != -1 else {
            Swift.print("❌ Failed to redirect stderr")
            close(pipe[0])
            close(pipe[1])
            close(originalStderr)
            return
        }
        
        close(pipe[1])
        
        DispatchQueue.global(qos: .utility).async {
            defer {
                close(pipe[0])
                close(originalStderr)
            }
            
            let fileHandle = FileHandle(fileDescriptor: pipe[0], closeOnDealloc: false)
            
            while true {
                let data = fileHandle.availableData
                if data.isEmpty { break }
                
                if let output = String(data: data, encoding: .utf8) {
                    self.writeToLog(output)
                    
                    // Write to original stderr
                    write(originalStderr, output, output.utf8.count)
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
    
    // Unsafe version for internal use when we know we're on the queue
    private func writeToLogUnsafe(_ message: String) {
        guard let data = message.data(using: .utf8),
              let handle = self._logFileHandle else { return }
        
        do {
            handle.write(data)
            // Check rotation after successful write
            if arc4random_uniform(100) == 0 { // Check occasionally to avoid overhead
                self.rotateLogIfNeeded()
            }
        } catch {
            Swift.print("❌ Write error: \(error)")
            // Handle could be invalid, try to recreate
            self.recreateFileHandle()
        }
    }
    
    private func writeToLog(_ message: String) {
        queue.async {
            self.writeToLogUnsafe(message)
        }
    }
    
    func forceFlush() {
        queue.async {
            do {
                self._logFileHandle?.synchronizeFile()
            } catch {
                Swift.print("❌ Flush error: \(error)")
                self.recreateFileHandle()
            }
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
        validateLogState()
    }

    func clearLog() {
        queue.async {
            self._logFileHandle?.closeFile()
            self._logFileHandle = nil
            try? FileManager.default.removeItem(at: self.logFileURL)
            
            // Recreate file and handle
            FileManager.default.createFile(atPath: self.logFileURL.path, contents: nil, attributes: nil)
            do {
                self._logFileHandle = try FileHandle(forWritingTo: self.logFileURL)
                self.writeToLogUnsafe("Log cleared by user\n")
            } catch {
                Swift.print("❌ Failed to recreate log after clear: \(error)")
            }
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
        
        // Close and nil the handle atomically
        _logFileHandle?.closeFile()
        _logFileHandle = nil
        
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
            
            // Create new log file
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
            
            // Recreate handle
            let newHandle = try FileHandle(forWritingTo: logFileURL)
            _logFileHandle = newHandle
            
            writeToLogUnsafe("📄 Log rotated from \(rotatedURL.lastPathComponent)\n")
        } catch {
            Swift.print("❌ Failed to rotate log: \(error)")
            // Try to recreate handle for current file
            recreateFileHandle()
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
                        self.writeToLogUnsafe("🧹 Deleted excess log: \(fileURL.lastPathComponent)\n")
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
                            self.writeToLogUnsafe("🧹 Deleted oversized log: \(fileURL.lastPathComponent)\n")
                        }
                    }
                }
                
            } catch {
                self.writeToLogUnsafe("❌ Failed to cleanup logs: \(error)\n")
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
                        self.writeToLogUnsafe("🧹 Deleted old log: \(fileURL.lastPathComponent)\n")
                    }
                }
            } catch {
                self.writeToLogUnsafe("❌ Failed to clean up old logs: \(error.localizedDescription)\n")
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
            self.validateLogState()
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
    // These can be used to replace print statements in your code if desired
    // Usage: LogManager.logInfo("message") instead of print("message")
    static func logInfo(_ message: String) {
        shared.info(message)
    }
    
    static func logDebug(_ message: String) {
        shared.debug(message)
    }
    
    static func logWarning(_ message: String) {
        shared.warning(message)
    }
    
    static func logError(_ message: String) {
        shared.error(message)
    }
}
