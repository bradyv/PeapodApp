//
//  EpisodeCell.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-09-12.
//

import SwiftUI

struct EpisodeCellData: Equatable {
    let id: String
    let title: String
    let podcastTitle: String
    let podcastImage: String
    let episodeImage: String?
    let airDate: Date
    let isPlayed: Bool
    let isQueued: Bool
    let isFav: Bool
    let feedUrl: String
    let episodeDescription: String
    
    init(from episode: Episode) {
        self.id = episode.id ?? ""
        self.title = episode.title ?? ""
        self.podcastTitle = episode.podcast?.title ?? ""
        self.podcastImage = episode.podcast?.image ?? ""
        self.episodeImage = episode.episodeImage
        self.airDate = episode.airDate ?? Date.distantPast
        self.isPlayed = episode.isPlayed
        self.isQueued = episode.isQueued
        self.isFav = episode.isFav
        self.feedUrl = episode.podcast?.feedUrl ?? ""
        self.episodeDescription = episode.episodeDescription ?? ""
    }
}

struct EpisodeCell: View {
    let data: EpisodeCellData
    let episode: Episode
    
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @EnvironmentObject var downloadManager: DownloadManager
    
    private var isDownloaded: Bool {
        guard let episodeId = episode.id else { return false }
        // Force dependency on published arrays to trigger updates
        let _ = episodesViewModel.downloaded
        return downloadManager.isDownloaded(episodeId: episodeId)
    }
    
    private var isDownloading: Bool {
        guard let episodeId = episode.id else { return false }
        // Force dependency on published dictionaries to trigger updates
        let _ = downloadManager.activeDownloads
        let _ = downloadManager.downloadQueue
        return downloadManager.isDownloading(episodeId: episodeId)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ArtworkView(
                url: data.episodeImage ?? data.podcastImage,
                size: 100,
                cornerRadius: 24,
                tilt: false
            )
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RoundedRelativeDateView(date: data.airDate)
                        .lineLimit(1)
                        .textDetailEmphasis()
                    
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .textDetail()
                    } else if isDownloading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    
                    if data.isFav {
                        Image(systemName: "heart.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.orange)
                            .textDetail()
                    } else if data.isPlayed {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.heading)
                                .textDetail()
                            
                            Text("Played")
                                .textDetail()
                        }
                    }
                }
                
                EpisodeDetails(data: data)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .contextMenu { contextMenuContent }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        ArchiveButton(episode: episode)
        MarkAsPlayedButton(episode: episode)
        FavButton(episode: episode)
        DownloadActionButton(episode: episode)
        
        Section(data.podcastTitle) {
            NavigationLink {
                PodcastDetailView(feedUrl: data.feedUrl)
            } label: {
                Label("View Podcast", systemImage: "widget.small")
            }
        }
    }
}

struct EmptyEpisodeCell: View {
    var body: some View {
        HStack(spacing: 16) {
            // Artwork
            SkeletonItem(width:100, height:100, cornerRadius:24)
            
            // Episode Meta
            VStack(alignment: .leading, spacing: 8) {
                // Podcast Title + Release
                HStack {
                    SkeletonItem(width:100, height:16, cornerRadius:4)
                    
                    SkeletonItem(width:50, height:14, cornerRadius:4)
                }
                
                // Episode Title + Description
                VStack(alignment: .leading, spacing: 2) {
                    SkeletonItem(width:200, height:20, cornerRadius:4)
                    
                    SkeletonItem(height:16, cornerRadius:4)
                    
                    SkeletonItem(height:16, cornerRadius:4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
