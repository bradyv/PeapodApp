//
//  DownloadManager.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-10-21.
//

import Foundation
import AVFoundation
import CoreData
import Combine

@MainActor
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    // MARK: - Published Properties
    @Published var activeDownloads: [String: DownloadProgress] = [:] // episodeId -> progress
    @Published var downloadQueue: [String] = [] // Queue of episode IDs waiting to download
    
    // MARK: - Private Properties
    private var urlSession: URLSession!
    private var activeDownloadTasks: [String: URLSessionDownloadTask] = [:]
    private let maxConcurrentDownloads = 3
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - File Management
    private var downloadsDirectory: URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: downloadsURL.path) {
            try? fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        }
        
        return downloadsURL
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.peapod.downloads")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        // Resume any incomplete downloads
        Task {
            await resumeIncompleteDownloads()
        }
        
        // Start cleanup timer
        startCleanupTimer()
    }
    
    // MARK: - Public API
    
    /// Download an episode for offline playback
    func downloadEpisode(_ episode: Episode) {
        guard let episodeId = episode.id,
              let audioURL = episode.audio,
              let url = URL(string: audioURL) else {
            LogManager.shared.error("❌ Cannot download episode: missing ID or audio URL")
            return
        }
        
        // Check if already downloaded
        if isDownloaded(episodeId: episodeId) {
            LogManager.shared.info("✅ Episode already downloaded: \(episode.title ?? "Unknown")")
            return
        }
        
        // Check if already downloading
        if activeDownloads[episodeId] != nil {
            LogManager.shared.info("⏳ Episode already downloading: \(episode.title ?? "Unknown")")
            return
        }
        
        // Add to queue if we're at max concurrent downloads
        if activeDownloadTasks.count >= maxConcurrentDownloads {
            if !downloadQueue.contains(episodeId) {
                downloadQueue.append(episodeId)
                LogManager.shared.info("📥 Added to download queue: \(episode.title ?? "Unknown")")
            }
            return
        }
        
        // Start download
        startDownload(episodeId: episodeId, url: url, episode: episode)
    }
    
    /// Cancel an ongoing download
    func cancelDownload(for episodeId: String) {
        // Cancel active task
        if let task = activeDownloadTasks[episodeId] {
            task.cancel()
            activeDownloadTasks.removeValue(forKey: episodeId)
        }
        
        // Remove from progress tracking
        activeDownloads.removeValue(forKey: episodeId)
        
        // Remove from queue
        downloadQueue.removeAll { $0 == episodeId }
        
        LogManager.shared.info("🚫 Cancelled download for episode: \(episodeId)")
        
        // Start next queued download
        processQueue()
        
        notifyDownloadUpdate()
    }
    
    /// Delete a downloaded episode
    func deleteDownload(for episodeId: String) {
        let fileURL = getLocalFileURL(for: episodeId)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
            LogManager.shared.info("🗑️ Deleted download for episode: \(episodeId)")
            
            notifyDownloadUpdate()
        }
    }
    
    /// Check if an episode is downloaded
    nonisolated func isDownloaded(episodeId: String) -> Bool {
        let fileURL = getLocalFileURL(for: episodeId)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    /// Get the local file URL for an episode (if downloaded)
    nonisolated func getLocalFileURL(for episodeId: String) -> URL {
        // Need to compute downloads directory without accessing @MainActor property
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        return downloadsURL.appendingPathComponent("\(episodeId).mp3")
    }
    
    /// Get download progress for an episode (0.0 to 1.0)
    func getProgress(for episodeId: String) -> Double {
        activeDownloads[episodeId]?.progress ?? 0.0
    }
    
    /// Check if an episode is currently downloading
    func isDownloading(episodeId: String) -> Bool {
        activeDownloads[episodeId] != nil
    }
    
    // MARK: - Private Methods
    
    private func startDownload(episodeId: String, url: URL, episode: Episode) {
        let task = urlSession.downloadTask(with: url)
        
        // Set task description to episode ID for resuming purposes
        task.taskDescription = episodeId
        
        // Track task
        activeDownloadTasks[episodeId] = task
        activeDownloads[episodeId] = DownloadProgress(episodeId: episodeId, progress: 0.0)
        
        // Start download
        task.resume()
        
        LogManager.shared.info("⬇️ Started download for: \(episode.title ?? "Unknown")")
    }
    
    private func processQueue() {
        guard activeDownloadTasks.count < maxConcurrentDownloads,
              !downloadQueue.isEmpty else {
            return
        }
        
        // Get next episode from queue
        let episodeId = downloadQueue.removeFirst()
        
        // Fetch episode from Core Data
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", episodeId)
        request.fetchLimit = 1
        
        if let episode = try? context.fetch(request).first,
           let audioURL = episode.audio,
           let url = URL(string: audioURL) {
            startDownload(episodeId: episodeId, url: url, episode: episode)
        }
    }
    
    private func resumeIncompleteDownloads() async {
        // Get all incomplete downloads from URLSession
        let tasks = await urlSession.allTasks
        
        // Filter to only download tasks that are still running
        let downloadTasks = tasks.compactMap { $0 as? URLSessionDownloadTask }
            .filter { $0.state == .running || $0.state == .suspended }
        
        for task in downloadTasks {
            if let episodeId = task.taskDescription {
                await MainActor.run {
                    activeDownloadTasks[episodeId] = task
                    activeDownloads[episodeId] = DownloadProgress(episodeId: episodeId, progress: 0.0)
                }
            }
        }
    }
    
    private func notifyDownloadUpdate() {
        NotificationCenter.default.post(name: .downloadDidUpdate, object: nil)
    }
    
    // MARK: - Cleanup
    
    private func startCleanupTimer() {
        // Run cleanup every hour
        Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.cleanupOldDownloads()
            }
            .store(in: &cancellables)
        
        // Also run cleanup on init
        cleanupOldDownloads()
    }
    
    private func cleanupOldDownloads() {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            let request: NSFetchRequest<Playback> = Playback.fetchRequest()
            request.predicate = NSPredicate(format: "isPlayed == YES AND playedDate != nil")
            
            guard let playbackStates = try? context.fetch(request) else { return }
            
            let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
            
            for playback in playbackStates {
                if let playedDate = playback.playedDate,
                   playedDate < twentyFourHoursAgo,
                   let episodeId = playback.episodeId {
                    
                    // Check if file actually exists before trying to delete
                    Task { @MainActor in
                        if self.isDownloaded(episodeId: episodeId) {
                            self.deleteDownload(for: episodeId)
                            LogManager.shared.info("🧹 Auto-deleted old download: \(episodeId)")
                        }
                    }
                }
            }
        }
    }
    
    /// Get preferred audio URL for playback (local file if available, otherwise remote URL)
    nonisolated func getPreferredAudioURL(for episode: Episode) -> URL? {
        guard let episodeId = episode.id else { return nil }
        
        // Check if downloaded
        if isDownloaded(episodeId: episodeId) {
            return getLocalFileURL(for: episodeId)
        }
        
        // Fall back to remote URL
        if let audioURL = episode.audio {
            return URL(string: audioURL)
        }
        
        return nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // CRITICAL: This must be SYNCHRONOUS - file copy BEFORE Task { @MainActor }
        
        // Get episode ID from task description
        guard let episodeId = downloadTask.taskDescription else {
            return
        }
        
        // Get destination URL
        let destinationURL = getLocalFileURL(for: episodeId)
        
        do {
            // Ensure Downloads directory exists
            let downloadsDir = destinationURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: downloadsDir.path) {
                try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
                LogManager.shared.info("📁 Created Downloads directory")
            }
            
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // COPY the file SYNCHRONOUSLY (not in Task)
            try FileManager.default.copyItem(at: location, to: destinationURL)
            
            LogManager.shared.info("✅ Download completed: \(episodeId)")
            
            // NOW update UI state (file is already copied and safe)
            Task { @MainActor in
                activeDownloads.removeValue(forKey: episodeId)
                activeDownloadTasks.removeValue(forKey: episodeId)
                processQueue()
                
                notifyDownloadUpdate()
            }
            
        } catch {
            LogManager.shared.error("❌ Failed to copy: \(error)")
            
            Task { @MainActor in
                activeDownloads.removeValue(forKey: episodeId)
                activeDownloadTasks.removeValue(forKey: episodeId)
                processQueue()
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            guard let episodeId = activeDownloadTasks.first(where: { $0.value == downloadTask })?.key else {
                return
            }
            
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            activeDownloads[episodeId]?.progress = progress
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        
        Task { @MainActor in
            guard let episodeId = activeDownloadTasks.first(where: { $0.value == task })?.key else {
                return
            }
            
            LogManager.shared.error("❌ Download failed for \(episodeId): \(error.localizedDescription)")
            
            // Clean up
            activeDownloads.removeValue(forKey: episodeId)
            activeDownloadTasks.removeValue(forKey: episodeId)
            
            // Process next queued download
            processQueue()
        }
    }
}

// MARK: - Supporting Types

struct DownloadProgress {
    let episodeId: String
    var progress: Double
}
