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

@MainActor
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    
    var interfaceController: CPInterfaceController?
    private let context = PersistenceController.shared.container.viewContext
    private var episodesViewModel: EpisodesViewModel?
    private var cancellables = Set<AnyCancellable>()
    
    // Template references
    private var upNextTemplate: CPListTemplate?
    private var favoritesTemplate: CPListTemplate?
    private var recentTemplate: CPListTemplate?
    private var libraryTemplate: CPListTemplate?
    
    // CRITICAL: Image cache to prevent flashing
    private var imageCache: [String: UIImage] = [:]
    private let imageCacheQueue = DispatchQueue(label: "carplay.imageCache", qos: .userInteractive)
    
    // CRITICAL: Update throttling to prevent excessive refreshes
    private var updateWorkItem: DispatchWorkItem?
    private let updateDebounceInterval: TimeInterval = 0.3
    
    // CRITICAL: Track currently playing episode to minimize updates
    private var lastPlayingEpisodeID: String?
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                 didConnect interfaceController: CPInterfaceController) {
        
        self.interfaceController = interfaceController
        
        print("🚗 CarPlay connected!")
        
        // Get episodes view model from AppDelegate
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            self.episodesViewModel = appDelegate.episodesViewModel
            setupDataObservers()
        }
        
        // Set up root template
        let rootTemplate = createTabBarTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: false, completion: nil)
        
        // Listen for Core Data changes (debounced)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
        
        // Listen for CarPlay play requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlayRequest),
            name: NSNotification.Name("PlayEpisodeFromCarPlay"),
            object: nil
        )
    }
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                 didDisconnect interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        
        imageCacheQueue.async { [weak self] in
            self?.imageCache.removeAll()
        }
        
        print("🚗 CarPlay disconnected")
    }
    
    // MARK: - Data Observers (Optimized)
    
    private func setupDataObservers() {
        guard let viewModel = episodesViewModel else { return }
        
        // Observe queue changes with deduplication
        viewModel.$queue
            .dropFirst()
            .removeDuplicates { old, new in
                old.map { $0.id } == new.map { $0.id }
            }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleUpdate {
                    self?.updateUpNextTemplate()  // FIX: Use self? here too
                }
            }
            .store(in: &cancellables)
        
        // Observe favorites changes
        viewModel.$favs
            .dropFirst()
            .removeDuplicates { old, new in
                old.map { $0.id } == new.map { $0.id }
            }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleUpdate {
                    self?.updateFavoritesTemplate()  // FIX
                }
            }
            .store(in: &cancellables)
        
        // Observe latest changes
        viewModel.$latest
            .dropFirst()
            .removeDuplicates { old, new in
                old.map { $0.id } == new.map { $0.id }
            }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleUpdate {
                    self?.updateRecentTemplate()  // FIX
                }
            }
            .store(in: &cancellables)
        
        // CRITICAL: Only update when playing state actually changes
        let player = AudioPlayerManager.shared
        
        Publishers.CombineLatest(
            player.$playbackState.map { $0.episodeID }.removeDuplicates(),
            player.$playbackState.map { $0.isPlaying }.removeDuplicates()
        )
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] episodeID, isPlaying in
            guard let self = self else { return }
            
            if self.lastPlayingEpisodeID != episodeID {
                self.lastPlayingEpisodeID = episodeID
                self.scheduleUpdate {
                    self.refreshAllTemplates()  // FIX: Remove the ? since we already unwrapped self
                }
            }
        }
        .store(in: &cancellables)
    }
    
    // MARK: - Update Scheduling (Debounced)
    
    private func scheduleUpdate(_ updateBlock: @escaping () -> Void) {
        updateWorkItem?.cancel()
        
        let workItem = DispatchWorkItem {
            updateBlock()
        }
        updateWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + updateDebounceInterval, execute: workItem)
    }
    
    @objc private func dataDidChange() {
        scheduleUpdate { [weak self] in
            self?.refreshAllTemplates()
        }
    }
    
    @objc private func handlePlayRequest(_ notification: Notification) {
        guard let episodeID = notification.object as? String else { return }
        
        // Find episode and play it
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", episodeID)
        request.fetchLimit = 1
        
        if let episode = try? context.fetch(request).first {
            AudioPlayerManager.shared.togglePlayback(for: episode, episodesViewModel: episodesViewModel)
        }
    }
    
    private func refreshAllTemplates() {
        updateUpNextTemplate()
        updateFavoritesTemplate()
        updateRecentTemplate()
        updateLibraryTemplate()
    }
    
    // MARK: - Template Updates (Batch Operations)
    
    private func updateUpNextTemplate() {
        guard let template = upNextTemplate else { return }
        let newSection = createUpNextSection()
        template.updateSections([newSection])
    }
    
    private func updateFavoritesTemplate() {
        guard let template = favoritesTemplate else { return }
        let newSection = createFavoritesSection()
        template.updateSections([newSection])
    }
    
    private func updateRecentTemplate() {
        guard let template = recentTemplate else { return }
        let newSection = createRecentSection()
        template.updateSections([newSection])
    }
    
    private func updateLibraryTemplate() {
        guard let template = libraryTemplate else { return }
        
        context.perform { [weak self] in
            guard let self = self else { return }
            
            let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
            request.predicate = NSPredicate(format: "isSubscribed == YES")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Podcast.title, ascending: true)]
            
            if let podcasts = try? self.context.fetch(request) {
                let items = podcasts.map { self.createPodcastItem(for: $0) }
                let section = CPListSection(items: items)
                
                DispatchQueue.main.async {
                    template.updateSections([section])
                }
            }
        }
    }
    
    // MARK: - Tab Bar Template
    
    private func createTabBarTemplate() -> CPTabBarTemplate {
        upNextTemplate = CPListTemplate(title: "Up Next", sections: [createUpNextSection()])
        upNextTemplate?.tabImage = UIImage(systemName: "play.square.stack")
        upNextTemplate?.emptyViewTitleVariants = ["Nothing Up Next"]
        
        favoritesTemplate = CPListTemplate(title: "Favorites", sections: [createFavoritesSection()])
        favoritesTemplate?.tabImage = UIImage(systemName: "heart.fill")
        favoritesTemplate?.emptyViewTitleVariants = ["No Favorites"]
        
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
    
    // MARK: - Sections (Background Fetching)
    
    private func createUpNextSection() -> CPListSection {
        // Use ViewModel first (already loaded)
        if let viewModel = episodesViewModel, !viewModel.queue.isEmpty {
            let items = viewModel.queue.prefix(20).map { createEpisodeItem(for: $0) }
            return CPListSection(items: items)
        }
        
        // Fallback to direct fetch
        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
        playbackRequest.predicate = NSPredicate(format: "isQueued == YES")
        playbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.queuePosition, ascending: true)]
        playbackRequest.fetchLimit = 20
        
        guard let playbackStates = try? context.fetch(playbackRequest) else {
            return CPListSection(items: [])
        }
        
        let episodeIds = playbackStates.compactMap { $0.episodeId }
        guard !episodeIds.isEmpty else {
            return CPListSection(items: [])
        }
        
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
        episodeRequest.relationshipKeyPathsForPrefetching = ["podcast"]
        
        guard let episodes = try? context.fetch(episodeRequest) else {
            return CPListSection(items: [])
        }
        
        // Sort by queue position
        let sortedEpisodes = episodes.sorted { e1, e2 in
            guard let id1 = e1.id, let id2 = e2.id else { return false }
            let pos1 = episodeIds.firstIndex(of: id1) ?? Int.max
            let pos2 = episodeIds.firstIndex(of: id2) ?? Int.max
            return pos1 < pos2
        }
        
        let items = sortedEpisodes.map { createEpisodeItem(for: $0) }
        return CPListSection(items: items)
    }
    
    private func createFavoritesSection() -> CPListSection {
        let playbackRequest: NSFetchRequest<Playback> = Playback.fetchRequest()
        playbackRequest.predicate = NSPredicate(format: "isFav == YES")
        playbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Playback.favDate, ascending: false)]
        playbackRequest.fetchLimit = 20
        
        guard let playbackStates = try? context.fetch(playbackRequest) else {
            return CPListSection(items: [])
        }
        
        let episodeIds = playbackStates.compactMap { $0.episodeId }
        guard !episodeIds.isEmpty else {
            return CPListSection(items: [])
        }
        
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        episodeRequest.predicate = NSPredicate(format: "id IN %@", episodeIds)
        episodeRequest.relationshipKeyPathsForPrefetching = ["podcast"]
        
        guard let episodes = try? context.fetch(episodeRequest) else {
            return CPListSection(items: [])
        }
        
        let items = episodes.map { createEpisodeItem(for: $0) }
        return CPListSection(items: items)
    }
    
    private func createRecentSection() -> CPListSection {
        let subscribedPodcastIds = getSubscribedPodcastIds(context: context)
        
        guard !subscribedPodcastIds.isEmpty else {
            return CPListSection(items: [])
        }
        
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId IN %@", subscribedPodcastIds)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchLimit = 20
        request.relationshipKeyPathsForPrefetching = ["podcast"]
        
        guard let episodes = try? context.fetch(request) else {
            return CPListSection(items: [])
        }
        
        let items = episodes.map { createEpisodeItem(for: $0) }
        return CPListSection(items: items)
    }
    
    private func createLibraryTemplate() -> CPListTemplate {
        let request: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        request.predicate = NSPredicate(format: "isSubscribed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Podcast.title, ascending: true)]
        
        let podcasts = (try? context.fetch(request)) ?? []
        let items = podcasts.map { createPodcastItem(for: $0) }
        
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Library", sections: [section])
        template.emptyViewTitleVariants = ["No Podcasts"]
        return template
    }
    
    // MARK: - List Items (Optimized)
    
    private func createEpisodeItem(for episode: Episode) -> CPListItem {
        let title = episode.title ?? "Untitled Episode"
        let subtitle = episode.podcast?.title ?? ""
        
        let item = CPListItem(text: title, detailText: subtitle)
        
        // CRITICAL: Only show playing indicator for the actual playing episode
        let player = AudioPlayerManager.shared
        if player.currentEpisode?.id == episode.id && player.isPlaying {
            item.setAccessoryImage(
                UIImage(systemName: "speaker.wave.2.fill")?
                    .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            )
        }
        
        // Load artwork with caching (non-blocking)
        if let artworkURL = episode.episodeImage ?? episode.podcast?.image {
            loadImageWithCaching(from: artworkURL, for: item)
        }
        
        // CRITICAL: Handler for instant playback
        item.handler = { [weak self] (item: any CPSelectableListItem, completion: @escaping () -> Void) in
            // Complete immediately for instant UI feedback
            completion()
            
            // Play episode
            self?.playEpisodeInstantly(episode)
        }
        
        return item
    }
    
    private func createPodcastItem(for podcast: Podcast) -> CPListItem {
        let title = podcast.title ?? "Untitled Podcast"
        let item = CPListItem(text: title, detailText: nil)
        
        if let artworkURL = podcast.image {
            loadImageWithCaching(from: artworkURL, for: item)
        }
        
        item.handler = { [weak self] (item: any CPSelectableListItem, completion: @escaping () -> Void) in
            completion()
            self?.showPodcastEpisodes(for: podcast)
        }
        
        return item
    }
    
    // MARK: - Actions (Instant)
    
    private func showPodcastEpisodes(for podcast: Podcast) {
        let request: NSFetchRequest<Episode> = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "podcastId == %@", podcast.id ?? "")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
        request.fetchLimit = 50
        request.relationshipKeyPathsForPrefetching = ["podcast"]
        
        guard let episodes = try? context.fetch(request) else { return }
        
        let items = episodes.map { createEpisodeItem(for: $0) }
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: podcast.title ?? "Episodes", sections: [section])
        
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }
    
    private func playEpisodeInstantly(_ episode: Episode) {
        // CRITICAL: Play immediately without any async operations
        AudioPlayerManager.shared.togglePlayback(for: episode, episodesViewModel: episodesViewModel)
        
        print("🚗 Playing: \(episode.title ?? "Unknown")")
    }
    
    // MARK: - Image Loading (Background + Cache)
    
    private func loadImageWithCaching(from urlString: String, for item: CPListItem) {
        guard let url = URL(string: urlString) else { return }
        
        // Check memory cache first (instant)
        if let cachedImage = imageCache[urlString] {
            item.setImage(cachedImage)
            return
        }
        
        // Load in background
        Task.detached(priority: .userInteractive) {
            // Use Kingfisher's efficient cache
            let result = try? await KingfisherManager.shared.retrieveImage(with: url)
            
            if let image = result?.image {
                // Resize on background thread
                let size = CGSize(width: 200, height: 200)
                let renderer = UIGraphicsImageRenderer(size: size)
                let resizedImage = renderer.image { context in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                
                // Cache in memory
                await self.cacheImage(resizedImage, for: urlString)
                
                // Update UI on main thread
                await MainActor.run {
                    item.setImage(resizedImage)
                }
            }
        }
    }
    
    private func cacheImage(_ image: UIImage, for key: String) async {
        await withCheckedContinuation { continuation in
            imageCacheQueue.async { [weak self] in
                self?.imageCache[key] = image
                continuation.resume()
            }
        }
    }
}
