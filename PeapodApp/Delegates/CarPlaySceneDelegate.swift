//
//  CarPlaySceneDelegate.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-10-04.
//

import Foundation
import CarPlay
import CoreData
import Combine
import Kingfisher

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    
    var interfaceController: CPInterfaceController?
    private let context = PersistenceController.shared.container.viewContext
    private var episodesViewModel: EpisodesViewModel?
    private var cancellables = Set<AnyCancellable>()
    
    // Keep references to templates for updates
    private var upNextTemplate: CPListTemplate?
    private var favoritesTemplate: CPListTemplate?
    private var recentTemplate: CPListTemplate?
    private var libraryTemplate: CPListTemplate?
    
    // Cache for resized images to prevent flashing
    private var imageCache: [String: UIImage] = [:]
    private let imageCacheQueue = DispatchQueue(label: "carplay.imageCache", qos: .userInteractive)
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                 didConnect interfaceController: CPInterfaceController) {
        
        self.interfaceController = interfaceController
        
        print("CarPlay connected!")
        
        // Get episodes view model from AppDelegate
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            self.episodesViewModel = appDelegate.episodesViewModel
            print("Got episodesViewModel with \(appDelegate.episodesViewModel.queue.count) queued episodes")
            
            // Set up observers for data changes
            setupDataObservers()
        }
        
        // Set up root template
        let rootTemplate = createTabBarTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: false, completion: nil)
        
        // Listen for Core Data changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
        
        // Force initial refresh after a short delay to ensure data is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshAllTemplates()
        }
    }
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                 didDisconnect interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        
        // Clear image cache on disconnect
        imageCacheQueue.async { [weak self] in
            self?.imageCache.removeAll()
        }
        
        print("CarPlay disconnected")
    }
    
    // MARK: - Data Observers
    
    private func setupDataObservers() {
        guard let viewModel = episodesViewModel else { return }
        
        // Observe queue changes - only update when episodes actually change
        viewModel.$queue
            .dropFirst()
            .removeDuplicates { old, new in
                // Only update if the episode IDs actually changed
                old.map { $0.id } == new.map { $0.id }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                print("Queue episodes changed in CarPlay: \(queue.count) episodes")
                self?.updateUpNextTemplate()
            }
            .store(in: &cancellables)
        
        // Same for favorites
        viewModel.$favs
            .dropFirst()
            .removeDuplicates { old, new in
                old.map { $0.id } == new.map { $0.id }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] favs in
                print("Favorites changed in CarPlay: \(favs.count) episodes")
                self?.updateFavoritesTemplate()
            }
            .store(in: &cancellables)
        
        // Same for latest
        viewModel.$latest
            .dropFirst()
            .removeDuplicates { old, new in
                old.map { $0.id } == new.map { $0.id }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latest in
                print("Latest changed in CarPlay: \(latest.count) episodes")
                self?.updateRecentTemplate()
            }
            .store(in: &cancellables)
        
        // Observe audio player changes to update accessory images
        let player = AudioPlayerManager.shared
        
        // Observe playback state changes
        player.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                print("Playback state changed in CarPlay")
                self?.refreshAllTemplates()
            }
            .store(in: &cancellables)
    }
    
    @objc private func dataDidChange() {
        print("Core Data changed, refreshing CarPlay templates")
        refreshAllTemplates()
    }
    
    private func refreshAllTemplates() {
        DispatchQueue.main.async { [weak self] in
            self?.updateUpNextTemplate()
            self?.updateFavoritesTemplate()
            self?.updateRecentTemplate()
            self?.updateLibraryTemplate()
        }
    }
    
    // MARK: - Template Updates
    
    private func updateUpNextTemplate() {
        guard let template = upNextTemplate else {
            print("No upNextTemplate reference")
            return
        }
        let newSection = createUpNextSection()
        print("Updating Up Next with \(newSection.items.count) items")
        template.updateSections([newSection])
    }
    
    private func updateFavoritesTemplate() {
        guard let template = favoritesTemplate else { return }
        let newSection = createFavoritesSection()
        print("Updating Favorites with \(newSection.items.count) items")
        template.updateSections([newSection])
    }
    
    private func updateRecentTemplate() {
        guard let template = recentTemplate else { return }
        let newSection = createRecentSection()
        print("Updating Recent with \(newSection.items.count) items")
        template.updateSections([newSection])
    }
    
    private func updateLibraryTemplate() {
        guard let template = libraryTemplate else { return }
        
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Podcast.title, ascending: true)]
        
        do {
            let podcasts = try context.fetch(request)
            let items = podcasts.map { podcast in
                createPodcastItem(for: podcast)
            }
            
            let section = CPListSection(items: items)
            template.updateSections([section])
        } catch {
            print("Failed to update library: \(error)")
        }
    }
    
    // MARK: - Tab Bar Template
    
    private func createTabBarTemplate() -> CPTabBarTemplate {
        upNextTemplate = CPListTemplate(title: "Up Next", sections: [createUpNextSection()])
        upNextTemplate?.tabImage = UIImage(systemName: "play.square.stack")
        upNextTemplate?.emptyViewTitleVariants = ["Nothing Up Next"]
        upNextTemplate?.emptyViewSubtitleVariants = ["New releases are automatically added"]
        
        favoritesTemplate = CPListTemplate(title: "Favorites", sections: [createFavoritesSection()])
        favoritesTemplate?.tabImage = UIImage(systemName: "heart.fill")
        favoritesTemplate?.emptyViewTitleVariants = ["No Favorites"]
        favoritesTemplate?.emptyViewSubtitleVariants = ["Tap the heart icon on any episode"]
        
        recentTemplate = CPListTemplate(title: "Recents", sections: [createRecentSection()])
        recentTemplate?.tabImage = UIImage(systemName: "clock.fill")
        recentTemplate?.emptyViewTitleVariants = ["No Recent Episodes"]
        
        libraryTemplate = createLibraryTemplate()
        libraryTemplate?.tabImage = UIImage(systemName: "books.vertical.fill")
        
        return CPTabBarTemplate(templates: [
            upNextTemplate!,
            favoritesTemplate!,
            recentTemplate!,
            libraryTemplate!
        ])
    }
    
    // MARK: - Sections
    
    private func createUpNextSection() -> CPListSection {
        // Try ViewModel first
        if let viewModel = episodesViewModel, !viewModel.queue.isEmpty {
            print("Using viewModel queue: \(viewModel.queue.count) episodes")
            let items = viewModel.queue.prefix(20).map { episode in
                createEpisodeItem(for: episode)
            }
            return CPListSection(items: items)
        }
        
        // Fallback to direct fetch using Playback boolean
        print("Falling back to direct fetch for queue")
        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
        playbackRequest.predicate = NSPredicate(format: "isQueued == YES")
        playbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.queuePosition, ascending: true)]
        
        do {
            let playbackStates = try context.fetch(playbackRequest)
            let episodeIds = playbackStates.compactMap { $0.episodeId }
            
            guard !episodeIds.isEmpty else {
                print("No queued episode IDs found")
                return CPListSection(items: [])
            }
            
            let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
            let episodes = try context.fetch(episodeRequest)
            
            // Sort by queue position
            let sortedEpisodes = episodes.sorted { e1, e2 in
                guard let id1 = e1.id, let id2 = e2.id else { return false }
                let pos1 = episodeIds.firstIndex(of: id1) ?? Int.max
                let pos2 = episodeIds.firstIndex(of: id2) ?? Int.max
                return pos1 < pos2
            }
            
            print("Direct fetch found \(sortedEpisodes.count) queued episodes")
            let items = sortedEpisodes.prefix(20).map { episode in
                createEpisodeItem(for: episode)
            }
            return CPListSection(items: items)
            
        } catch {
            print("Failed to fetch queue: \(error)")
            return CPListSection(items: [])
        }
    }
    
    private func createFavoritesSection() -> CPListSection {
        // Direct fetch using Playback boolean
        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
        playbackRequest.predicate = NSPredicate(format: "isFav == YES")
        playbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.favDate, ascending: false)]
        
        do {
            let playbackStates = try context.fetch(playbackRequest)
            let episodeIds = playbackStates.compactMap { $0.episodeId }
            
            guard !episodeIds.isEmpty else {
                return CPListSection(items: [])
            }
            
            let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
            episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
            let episodes = try context.fetch(episodeRequest)
            
            print("Found \(episodes.count) favorite episodes")
            let items = episodes.prefix(20).map { episode in
                createEpisodeItem(for: episode)
            }
            return CPListSection(items: items)
            
        } catch {
            print("Failed to fetch favorites: \(error)")
            return CPListSection(items: [])
        }
    }
    
    private func createRecentSection() -> CPListSection {
        // Direct fetch from Core Data instead of relying on ViewModel
        let subscribedPodcastIds = getSubscribedPodcastIds(context: context)
        
        guard !subscribedPodcastIds.isEmpty else {
            print("No subscribed podcasts for Recent")
            return CPListSection(items: [])
        }
        
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId IN %@", subscribedPodcastIds)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchLimit = 20
        
        do {
            let episodes = try context.fetch(request)
            print("Found \(episodes.count) recent episodes")
            let items = episodes.map { episode in
                createEpisodeItem(for: episode)
            }
            return CPListSection(items: items)
        } catch {
            print("Failed to fetch recent episodes: \(error)")
            return CPListSection(items: [])
        }
    }
    
    private func createLibraryTemplate() -> CPListTemplate {
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Podcast.title, ascending: true)]
        
        do {
            let podcasts = try context.fetch(request)
            let items = podcasts.map { podcast in
                createPodcastItem(for: podcast)
            }
            
            let section = CPListSection(items: items)
            let template = CPListTemplate(title: "Library", sections: [section])
            template.emptyViewTitleVariants = ["No Podcasts"]
            template.emptyViewSubtitleVariants = ["Subscribe to podcasts in the app"]
            return template
            
        } catch {
            print("Failed to fetch podcasts for CarPlay: \(error)")
            return CPListTemplate(title: "Library", sections: [])
        }
    }
    
    // MARK: - List Items
    
    private func createEpisodeItem(for episode: Episode) -> CPListItem {
        let title = episode.title ?? "Untitled Episode"
        let subtitle = episode.podcast?.title ?? ""
        
        let item = CPListItem(text: title, detailText: subtitle)
        
        // Check if this is the currently playing episode
        let player = AudioPlayerManager.shared
        let isCurrentlyPlaying = player.currentEpisode?.id == episode.id
        
        if isCurrentlyPlaying {
            // Show playing indicator
            if player.isPlaying {
                item.setAccessoryImage(
                    UIImage(systemName: "speaker.wave.2.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal))
            }
        }
        
        // Load artwork with caching to prevent flashing
        if let artworkURL = episode.episodeImage ?? episode.podcast?.image {
            loadImageWithCaching(from: artworkURL, for: item)
        }
        
        // Handle tap to play episode
        item.handler = { [weak self] (item: any CPSelectableListItem, completion: @escaping () -> Void) in
            self?.playEpisode(episode)
            completion()
        }
        
        return item
    }
    
    private func createPodcastItem(for podcast: Podcast) -> CPListItem {
        let title = podcast.title ?? "Untitled Podcast"
        let item = CPListItem(text: title, detailText: nil)
        
        // Load artwork with caching to prevent flashing
        if let artworkURL = podcast.image {
            loadImageWithCaching(from: artworkURL, for: item)
        }
        
        // Handle tap to show podcast episodes
        item.handler = { [weak self] (item: any CPSelectableListItem, completion: @escaping () -> Void) in
            self?.showPodcastEpisodes(for: podcast)
            completion()
        }
        
        return item
    }
    
    // MARK: - Actions
    
    private func showPodcastEpisodes(for podcast: Podcast) {
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchLimit = 50
        
        do {
            let episodes = try context.fetch(request)
            let items = episodes.map { episode in
                createEpisodeItem(for: episode)
            }
            
            let section = CPListSection(items: items)
            let template = CPListTemplate(title: podcast.title ?? "Episodes", sections: [section])
            
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
            
        } catch {
            print("Failed to fetch episodes for podcast: \(error)")
        }
    }
    
    private func playEpisode(_ episode: Episode) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("PlayEpisodeFromCarPlay"),
                object: episode.id
            )
            print("Posted CarPlay play request for: \(episode.title ?? "Unknown")")
            
            // Force Now Playing update after playback starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let player = AudioPlayerManager.shared
                if player.currentEpisode?.id == episode.id {
                    // Trigger a manual update to ensure CarPlay gets the info
                    player.objectWillChange.send()
                }
            }
        }
    }
    
    // MARK: - Image Loading
    
    private func loadImageWithCaching(from urlString: String, for item: CPListItem) {
        guard let url = URL(string: urlString) else { return }
        
        // Check cache first
        if let cachedImage = imageCache[urlString] {
            item.setImage(cachedImage)
            return
        }
        
        // Load from Kingfisher cache or network
        loadImage(from: url) { [weak self] image in
            DispatchQueue.main.async {
                if let image = image {
                    // Cache the resized image
                    self?.imageCacheQueue.async {
                        self?.imageCache[urlString] = image
                    }
                    item.setImage(image)
                }
            }
        }
    }
    
    private func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        // Use Kingfisher's cache
        KingfisherManager.shared.retrieveImage(with: url) { result in
            switch result {
            case .success(let imageResult):
                // Resize for CarPlay on background queue to avoid blocking
                DispatchQueue.global(qos: .userInteractive).async {
                    let image = imageResult.image
                    let size = CGSize(width: 200, height: 200)
                    
                    let renderer = UIGraphicsImageRenderer(size: size)
                    let resizedImage = renderer.image { context in
                        image.draw(in: CGRect(origin: .zero, size: size))
                    }
                    
                    DispatchQueue.main.async {
                        completion(resizedImage)
                    }
                }
            case .failure(let error):
                print("Failed to load image: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}
