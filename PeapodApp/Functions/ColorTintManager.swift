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
              let imageUrl = URL(string: imageUrlString),
              !imageUrlString.isEmpty else { return }

        KingfisherManager.shared.retrieveImage(with: imageUrl) { result in
            switch result {
            case .success(let value):
                if let variants = ColorExtractor.extractColorVariants(from: value.image) {
                    DispatchQueue.main.async {
                        podcast.podcastTint = variants.accent
                        try? context.save()
                    }
                }
            case .failure:
                break
            }
        }
    }

    static func applyTintIfNeeded(to episode: Episode, in context: NSManagedObjectContext) {
        // Only extract tint if episode has its own image and no tint yet
        guard episode.episodeTint == nil,
              let feedImage = episode.episodeImage,
              !feedImage.isEmpty,
              let imageUrl = URL(string: feedImage) else { return }

        KingfisherManager.shared.retrieveImage(with: imageUrl) { result in
            switch result {
            case .success(let value):
                if let variants = ColorExtractor.extractColorVariants(from: value.image) {
                    DispatchQueue.main.async {
                        episode.episodeTint = variants.accent
                        try? context.save()
                    }
                }
            case .failure:
                break
            }
        }
    }
}
