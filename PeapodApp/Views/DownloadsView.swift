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
    
    @FetchRequest(
        entity: Episode.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
    ) var allEpisodes: FetchedResults<Episode>
    
    // Filter to only show actually downloaded episodes
    var downloadedEpisodes: [Episode] {
        let _ = downloadManager.activeDownloads
        let _ = downloadManager.downloadQueue
        return allEpisodes.filter { $0.isDownloaded || $0.isDownloading }
    }
    
    var body: some View {
        List {
            if downloadedEpisodes.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloaded episodes will appear here")
                )
            } else {
                Section {
                    ForEach(downloadedEpisodes) { episode in
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
                                    downloadManager.deleteDownload(for: episodeId)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
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
        for episode in downloadedEpisodes {
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
        episode.isDownloading
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
