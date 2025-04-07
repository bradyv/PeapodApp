//
//  ColorTintManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher
@preconcurrency import CoreData

enum ColorTintManager {
    static func applyTintIfNeeded(to podcast: Podcast, in context: NSManagedObjectContext) {
        guard podcast.podcastTint == nil,
              let imageUrlString = podcast.image,
              !imageUrlString.isEmpty,
              let imageUrl = URL(string: imageUrlString) else { return }

        // Only pass Sendable types (URL + objectID)
        let objectID = podcast.objectID

        KingfisherManager.shared.retrieveImage(with: imageUrl) { result in
            switch result {
            case .success(let value):
                if let variants = ColorExtractor.extractColorVariants(from: value.image) {
                    context.perform {
                        if let object = try? context.existingObject(with: objectID) as? Podcast {
                            object.podcastTint = variants.accent
                            try? context.save()
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }

    static func applyTintIfNeeded(to episode: Episode, in context: NSManagedObjectContext) {
        guard episode.episodeTint == nil,
              let feedImage = episode.episodeImage,
              !feedImage.isEmpty,
              let imageUrl = URL(string: feedImage) else { return }

        let objectID = episode.objectID

        KingfisherManager.shared.retrieveImage(with: imageUrl) { result in
            switch result {
            case .success(let value):
                if let variants = ColorExtractor.extractColorVariants(from: value.image) {
                    context.perform {
                        if let object = try? context.existingObject(with: objectID) as? Episode {
                            object.episodeTint = variants.accent
                            try? context.save()
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }
}
