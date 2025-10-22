//
//  EpisodeActions.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-10-08.
//

import SwiftUI

struct ArchiveButton: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var episode: Episode
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @EnvironmentObject var player: AudioPlayerManager
    
    var body: some View {
        Button {
            if episode.isQueued {
                // Check if this episode is the current episode (playing or paused)
                if player.currentEpisode?.id == episode.id {
                    player.stop()
                }
                
                withAnimation {
                    removeFromQueue(episode, episodesViewModel: episodesViewModel)
                }
            } else {
                withAnimation {
                    toggleQueued(episode, episodesViewModel: episodesViewModel)
                }
            }
        } label: {
            Label(episode.isQueued ? "Archive" : "Add to Up Next", systemImage:episode.isQueued ? "rectangle.portrait.on.rectangle.portrait.slash" : "rectangle.portrait.on.rectangle.portrait.angled")
        }
    }
}

struct MarkAsPlayedButton: View {
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    
    var body: some View {
        Button(action: {
            if episode.isPlayed {
                player.markAsUnplayed(for:episode)
            } else {
                if episode.isQueued {
                    withAnimation {
                        removeFromQueue(episode, episodesViewModel: episodesViewModel)
                    }
                }
                player.markAsPlayed(for: episode, manually: true)
            }
        }) {
            Label(episode.isPlayed ? "Mark Unplayed" : "Mark as Played", systemImage: episode.isPlayed ? "checkmark.arrow.trianglehead.counterclockwise" : "checkmark.circle")
                .contentTransition(.symbolEffect(.replace))
                .textButton()
        }
    }
}

struct FavButton: View {
    @ObservedObject var episode: Episode
    
    var body: some View {
        Button(action: {
            withAnimation {
                toggleFav(episode)
            }
        }) {
            Label(episode.isFav ? "Undo Favorite" : "Favorite", systemImage: episode.isFav ? "heart.slash" : "heart")
                .textButton()
        }
    }
}

struct DownloadActionButton: View {
    @ObservedObject var episode: Episode
    @EnvironmentObject var downloadManager: DownloadManager
    
    var body: some View {
        Button {
            handleDownloadAction()
        } label: {
            if episode.isDownloaded {
                Label("Delete Download", systemImage: "trash")
            } else if episode.isDownloading {
                Label("Cancel Download", systemImage: "xmark.circle")
            } else {
                Label("Download Episode", systemImage: "arrow.down.circle")
            }
        }
    }
    
    private func handleDownloadAction() {
        guard let episodeId = episode.id else { return }
        
        withAnimation {
            if episode.isDownloaded {
                downloadManager.deleteDownload(for: episodeId)
            } else if episode.isDownloading {
                downloadManager.cancelDownload(for: episodeId)
            } else {
                downloadManager.downloadEpisode(episode)
            }
        }
    }
}
