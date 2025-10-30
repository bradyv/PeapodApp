//
//  DownloadsView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-10-21.
//

import SwiftUI
import CoreData

struct DownloadsView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    
    var allDownloadEpisodes: [Episode] {
        var episodes = episodesViewModel.downloaded
        
        // Add episodes that are currently downloading (from active downloads + queue)
        let downloadingIds = Set(downloadManager.activeDownloads.keys)
        let queuedIds = Set(downloadManager.downloadQueue)
        let allDownloadingIds = downloadingIds.union(queuedIds)
        
        // Fetch episodes for downloading IDs
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", Array(allDownloadingIds))
        
        if let downloadingEpisodes = try? context.fetch(request) {
            // Add downloading episodes that aren't already in the downloaded list
            for episode in downloadingEpisodes {
                if !episodes.contains(where: { $0.id == episode.id }) {
                    episodes.append(episode)
                }
            }
        }
        
        // Sort by air date descending
        return episodes.sorted { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) }
    }
    
    var body: some View {
        List {
            if allDownloadEpisodes.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloaded episodes will appear here")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(allDownloadEpisodes) { episode in
                        NavigationLink {
                            EpisodeView(episode: episode)
                        } label: {
                            DownloadCellWithProgress(episode: episode)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if let episodeId = episode.id {
                                    if downloadManager.isDownloading(episodeId: episodeId) {
                                        downloadManager.cancelDownload(for: episodeId)
                                    } else {
                                        downloadManager.deleteDownload(for: episodeId)
                                    }
                                }
                            } label: {
                                if let episodeId = episode.id, downloadManager.isDownloading(episodeId: episodeId) {
                                    Label("Cancel", systemImage: "xmark")
                                } else {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Downloads are deleted 24 hours after an episode is played.")
                        .textDetail()
                }
                
                Section {
                    Button("Delete All Downloads", role: .destructive) {
                        deleteAllDownloads()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .listStyle(.plain)
        .background(Color.background)
        .navigationTitle("Downloads")
    }
    
    private func deleteAllDownloads() {
        // Cancel all active downloads
        for episodeId in downloadManager.activeDownloads.keys {
            downloadManager.cancelDownload(for: episodeId)
        }
        
        // Delete all downloaded files
        for episode in episodesViewModel.downloaded {
            if let episodeId = episode.id {
                downloadManager.deleteDownload(for: episodeId)
            }
        }
    }
}

struct DownloadCellWithProgress: View {
    @ObservedObject var episode: Episode
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    
    private var progress: Double {
        guard let episodeId = episode.id else { return 0.0 }
        return downloadManager.getProgress(for: episodeId)
    }
    
    private var isDownloading: Bool {
        guard let episodeId = episode.id else { return false }
        return downloadManager.isDownloading(episodeId: episodeId)
    }
    
    var body: some View {
        ZStack(alignment:.leading) {
            EpisodeCell(
                data: EpisodeCellData(from: episode),
                episode: episode
            )
            
            if isDownloading {
                VStack {
                    Text("\(Int(progress * 100))%")
                        .textDetailEmphasis()
                        .padding(.horizontal)
                    
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .padding(.horizontal)
                }
                .frame(width:100,height:100)
                .background(.black.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius:24))
            }
        }
    }
}
