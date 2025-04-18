//
//  AddToQueue.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-08.
//

import CoreData

func getQueuePlaylist(in context: NSManagedObjectContext) -> Playlist {
    let request = Playlist.fetchRequest()
    request.predicate = NSPredicate(format: "name == %@", "Queue")
    request.fetchLimit = 1

    if let playlist = try? context.fetch(request).first {
        return playlist
    }

    let newPlaylist = Playlist(context: context)
    newPlaylist.id = UUID()
    newPlaylist.name = "Queue"
    try? context.save()
    return newPlaylist
}

func addToQueue(_ episode: Episode, prepend: Bool = false, in context: NSManagedObjectContext) {
    let playlist = getQueuePlaylist(in: context)

    guard episode.playlist != playlist else { return }

    episode.playlist = playlist

    let episodes = (playlist.episodes as? Set<Episode>) ?? []
    let sorted = episodes.sorted { $0.queuePosition < $1.queuePosition }

    if prepend {
        episode.queuePosition = (sorted.first?.queuePosition ?? 0) - 1
    } else {
        episode.queuePosition = (sorted.last?.queuePosition ?? -1) + 1
    }
    
    episode.isQueued = true

    try? context.save()
}

func removeFromQueue(_ episode: Episode, in context: NSManagedObjectContext) {
    episode.playlist = nil
    episode.isQueued = false
    episode.queuePosition = -1
    try? context.save()
}

func normalizeQueuePositions(in context: NSManagedObjectContext) {
    let playlist = getQueuePlaylist(in: context)
    let episodes = (playlist.episodes as? Set<Episode>)?.sorted(by: { $0.queuePosition < $1.queuePosition }) ?? []
    for (index, ep) in episodes.enumerated() {
        ep.queuePosition = Int64(index)
    }
    try? context.save()
}

func moveToNowPlaying(_ episode: Episode, context: NSManagedObjectContext) {
    episode.nowPlayingItem = true

    let originalPlaylist = episode.playlist
    episode.playlist = nil

    // delay re-association to Playlist
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        episode.playlist = originalPlaylist
        try? context.save()
    }
}
