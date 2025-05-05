//
//  FetchRequests.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-28.
//

import SwiftUI
import CoreData

extension Episode {
    static func queueFetchRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "playlist.name == %@", "Queue")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.queuePosition, ascending: true)]
        request.fetchBatchSize = 20
        return request
    }
    
    static func latestEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcast != nil AND podcast.isSubscribed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchBatchSize = 20
        return request
    }
    
    static func unplayedEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcast != nil AND podcast.isSubscribed == YES AND isPlayed == NO AND playbackPosition == 0 AND nowPlaying = NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchBatchSize = 20
        return request
    }
    
    static func savedEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "isSaved == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.savedDate, ascending: false)]
        request.fetchBatchSize = 20
        return request
    }
    
    static func oldEpisodesRequest() -> NSFetchRequest<Episode> {
        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "(podcast = nil OR podcast.isSubscribed != YES) AND isSaved == NO AND isPlayed == NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.id, ascending: true)]
        request.fetchBatchSize = 20
        return request
    }
}

extension Podcast {
    static func subscriptionsFetchRequest() -> NSFetchRequest<Podcast> {
        let request = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Podcast.title, ascending: true)]
        request.fetchBatchSize = 20
        return request
    }
}

extension User {
    static func userSinceRequest(date: Date) -> NSFetchRequest<User> {
        let request = User.fetchRequest()
        request.predicate = NSPredicate(format: "userSince == %@", date as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \User.userSince, ascending: true)]
        return request
    }
    
    static func userTypeRequest(type: String) -> NSFetchRequest<User> {
        let request = User.fetchRequest()
        request.predicate = NSPredicate(format: "userType == %@", type)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \User.userType, ascending: true)]
        return request
    }
}

// Episode example
// @FetchRequest(fetchRequest: Episode.queueFetchRequest(), animation: .interactiveSpring())
// var queue: FetchedResults<Episode>

// Podcast example
// @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest(), animation: .interactiveSpring)
// var subscriptions: FetchedResults<Podcast>
