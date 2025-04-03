//
//  PreviewPersistence.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import CoreData

enum PreviewPersistenceController {
    static func makeContainer() -> NSPersistentContainer {
        let model = NSManagedObjectModel()

        // MARK: - Podcast Entity
        let podcastEntity = NSEntityDescription()
        podcastEntity.name = "Podcast"
        podcastEntity.managedObjectClassName = "Podcast"

        let podcastId = NSAttributeDescription()
        podcastId.name = "id"
        podcastId.attributeType = .stringAttributeType
        podcastId.isOptional = false

        let title = NSAttributeDescription()
        title.name = "title"
        title.attributeType = .stringAttributeType
        title.isOptional = false

        let author = NSAttributeDescription()
        author.name = "author"
        author.attributeType = .stringAttributeType
        author.isOptional = false

        let image = NSAttributeDescription()
        image.name = "image"
        image.attributeType = .stringAttributeType
        image.isOptional = false

        let podcastDescription = NSAttributeDescription()
        podcastDescription.name = "podcastDescription"
        podcastDescription.attributeType = .stringAttributeType
        podcastDescription.isOptional = false

        let feedUrl = NSAttributeDescription()
        feedUrl.name = "feedUrl"
        feedUrl.attributeType = .stringAttributeType
        feedUrl.isOptional = false

        let isSubscribed = NSAttributeDescription()
        isSubscribed.name = "isSubscribed"
        isSubscribed.attributeType = .booleanAttributeType
        isSubscribed.isOptional = false

        podcastEntity.properties = [podcastId, title, author, image, podcastDescription, feedUrl, isSubscribed]

        // MARK: - Episode Entity
        let episodeEntity = NSEntityDescription()
        episodeEntity.name = "Episode"
        episodeEntity.managedObjectClassName = "Episode"

        let episodeId = NSAttributeDescription()
        episodeId.name = "id"
        episodeId.attributeType = .stringAttributeType
        episodeId.isOptional = false

        let episodeTitle = NSAttributeDescription()
        episodeTitle.name = "title"
        episodeTitle.attributeType = .stringAttributeType
        episodeTitle.isOptional = false

        let duration = NSAttributeDescription()
        duration.name = "duration"
        duration.attributeType = .integer64AttributeType
        duration.isOptional = false

        let audio = NSAttributeDescription()
        audio.name = "audio"
        audio.attributeType = .stringAttributeType
        audio.isOptional = false

        let episodeImage = NSAttributeDescription()
        episodeImage.name = "episodeImage"
        episodeImage.attributeType = .stringAttributeType
        episodeImage.isOptional = true

        let airDate = NSAttributeDescription()
        airDate.name = "airDate"
        airDate.attributeType = .dateAttributeType
        airDate.isOptional = false

        let isQueued = NSAttributeDescription()
        isQueued.name = "isQueued"
        isQueued.attributeType = .booleanAttributeType
        isQueued.isOptional = false

        let hasBeenSeen = NSAttributeDescription()
        hasBeenSeen.name = "hasBeenSeen"
        hasBeenSeen.attributeType = .booleanAttributeType
        hasBeenSeen.isOptional = false

        // MARK: - Relationships
        let toPodcast = NSRelationshipDescription()
        toPodcast.name = "podcast"
        toPodcast.destinationEntity = podcastEntity
        toPodcast.minCount = 0
        toPodcast.maxCount = 1
        toPodcast.deleteRule = .nullifyDeleteRule
        toPodcast.inverseRelationship = nil // will link below

        let toEpisodes = NSRelationshipDescription()
        toEpisodes.name = "episode"
        toEpisodes.destinationEntity = episodeEntity
        toEpisodes.minCount = 0
        toEpisodes.maxCount = 0 // means to-many
        toEpisodes.isOrdered = true
        toEpisodes.deleteRule = .cascadeDeleteRule
        toEpisodes.inverseRelationship = toPodcast

        toPodcast.inverseRelationship = toEpisodes

        episodeEntity.properties = [episodeId, episodeTitle, duration, audio, episodeImage, airDate, isQueued, hasBeenSeen, toPodcast]
        podcastEntity.properties.append(toEpisodes)

        // Add both entities to the model
        model.entities = [podcastEntity, episodeEntity]

        let container = NSPersistentContainer(name: "PreviewModel", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Preview store failed: \(error)")
            }
        }

        return container
    }
}
