//
//  PodcastDetailView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import FeedKit
import Kingfisher

struct PodcastDetailView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var context
    @FetchRequest var podcastResults: FetchedResults<Podcast>
    @State private var episodes: [Episode] = []
    @State private var selectedEpisode: Episode? = nil
    @State var showFullDescription: Bool = false
    @State private var showSearch = false
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedDetent: PresentationDetent = .medium
    var podcast: Podcast? { podcastResults.first }
    var namespace: Namespace.ID

    init(feedUrl: String, namespace: Namespace.ID) {
        _podcastResults = FetchRequest<Podcast>(
            entity: Podcast.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "feedUrl == %@", feedUrl),
            animation: .default
        )
        self.namespace = namespace
    }

    var body: some View {
        VStack {
            if let podcast {
                if showSearch {
                    VStack(alignment:.leading) {
                        PodcastEpisodeSearchView(podcast: podcast, showSearch: $showSearch, selectedEpisode: $selectedEpisode, namespace: namespace)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                    .padding()
                } else {
                    ZStack {
                        ScrollView {
//                            Color.clear
//                                .frame(height: 1)
//                                .trackScrollOffset("scroll") { value in
//                                    scrollOffset = value
//                                }
                            Spacer().frame(height:32)
                            FadeInView(delay: 0.1) {
                                VStack(alignment:.leading) {
                                    KFImage(URL(string: podcast.image ?? ""))
                                        .resizable()
                                        .frame(width: 128, height: 128)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25), lineWidth: 1))
                                        .shadow(color:Color.tint(for:podcast),
                                                radius: 128
                                        )
                                }
                                .frame(maxWidth:.infinity, alignment:.leading)
                            }
                            
//                            Spacer().frame(height:128)
                            
                            FadeInView(delay: 0.2) {
                                VStack(alignment:.leading) {
                                    Text(podcast.title ?? "Podcast title")
                                        .titleSerif()
                                }
                                .frame(maxWidth:.infinity, alignment:.leading)
                                .padding(.bottom,12)
                            }
                            
                            FadeInView(delay: 0.3) {
                                Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
                                    .textBody()
                                    .lineLimit(showFullDescription ? nil :  4)
                                    .frame(maxWidth:.infinity, alignment:.leading)
                                    .onTapGesture {
                                        withAnimation {
                                            showFullDescription.toggle()
                                        }
                                    }
                                    .transition(.opacity)
                                    .animation(.easeOut(duration: 0.15), value: showFullDescription)
                                
                                Spacer().frame(height:24)
                            }
                            
                            LazyVStack(alignment: .leading) {
                                if let latestEpisode = episodes.first {
                                    FadeInView(delay: 0.4) {
                                        Text("Latest Episode")
                                            .headerSection()
                                    }
                                    
                                    FadeInView(delay: 0.5) {
                                        NavigationLink {
                                            PPPopover(pushView:false) {
                                                EpisodeView(episode: latestEpisode, namespace: namespace)
                                            }
                                            .navigationTransition(.zoom(sourceID: latestEpisode.id, in: namespace))
                                        } label: {
                                            EpisodeItem(episode: latestEpisode, namespace: namespace)
                                                .lineLimit(3)
                                                .padding(.bottom, 24)
                                                .matchedTransitionSource(id: latestEpisode.id, in: namespace)
                                        }
                                    }
                                }
                                
                                let remainingEpisodes = Array(episodes.dropFirst())
                                
                                if !remainingEpisodes.isEmpty {
                                    FadeInView(delay: 0.6) {
                                        Text("Episodes")
                                            .headerSection()
                                    }
                                    
                                    FadeInView(delay: 0.7) {
                                        ForEach(remainingEpisodes, id: \.id) { episode in
                                            FadeInView(delay: 0.3) {
                                                NavigationLink {
                                                    PPPopover(pushView:false) {
                                                        EpisodeView(episode: episode, namespace: namespace)
                                                    }
                                                    .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
                                                } label: {
                                                    EpisodeItem(episode: episode, namespace: namespace)
                                                        .lineLimit(3)
                                                        .padding(.bottom, 24)
                                                        .matchedTransitionSource(id: episode.id, in: namespace)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .coordinateSpace(name: "scroll")
                        .contentMargins(16, for: .scrollContent)
                        .maskEdge(.top)
                        .maskEdge(.bottom)
                        .transition(.opacity)
                        .frame(maxWidth:.infinity)
                        .onAppear {
                            let episodesArray = (podcast.episode as? Set<Episode>)?.sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) }) ?? []
                            episodes = episodesArray
                            
                            Task.detached(priority: .background) {
                                await ColorTintManager.applyTintIfNeeded(to: podcast, in: context)
                                
                                await EpisodeRefresher.refreshPodcastEpisodes(for: podcast, context: context) {
                                    DispatchQueue.main.async {
                                        let episodesArray = (podcast.episode as? Set<Episode>)?.sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) }) ?? []
                                        episodes = episodesArray
                                    }
                                }
                            }
                        }
                        
//                        VStack(alignment:.leading) {
//                            let minSize: CGFloat = 64
//                            let maxSize: CGFloat = 172
//                            let threshold: CGFloat = 72
//                            let shrink = max(minSize, min(maxSize, maxSize + min(0, scrollOffset - threshold)))
//                            Spacer().frame(height:52)
//                            KFImage(URL(string: podcast.image ?? ""))
//                                .resizable()
//                                .frame(width: shrink, height: shrink)
//                                .clipShape(RoundedRectangle(cornerRadius: 16))
//                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25), lineWidth: 1))
//                                .shadow(color:Color.tint(for:podcast),
//                                        radius: 128
//                                )
//                                .animation(.easeOut(duration: 0.1), value: shrink)
//                            Spacer()
//                        }
//                        .frame(maxWidth:.infinity, alignment:.leading)
//                        .padding(.horizontal)
                        
                        VStack {
                            HStack(alignment:.top) {
                                Spacer()
                                
                                HStack {
                                    Button(action: {
                                        showSearch.toggle()
                                    }) {
                                        Label("Search \(podcast.title ?? "episodes")", systemImage: "text.magnifyingglass")
                                    }
                                    .buttonStyle(PPButton(type: .transparent, colorStyle: .monochrome, iconOnly: true))
                                    
                                    Button(action: {
                                        podcast.isSubscribed.toggle()
                                        if podcast.isSubscribed,
                                           let latest = (podcast.episode as? Set<Episode>)?
                                            .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) })
                                            .first {
                                            toggleQueued(latest)
                                        }
                                        try? podcast.managedObjectContext?.save()
                                    }) {
                                        Text(podcast.isSubscribed ? "Unfollow" : "Follow")
                                    }
                                    .buttonStyle(PPButton(type: podcast.isSubscribed ? .transparent : .filled, colorStyle: .monochrome))
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .animation(.interactiveSpring(duration: 0.25), value: showSearch)
        .onAppear {
            print("PodcastDetailView feedUrl: \(podcast?.feedUrl ?? "none")")
            print("PodcastDetailView objectID: \(podcast?.objectID.uriRepresentation().absoluteString)")
            print("isSubscribed: \(podcast?.isSubscribed ?? false ? "YES" : "NO")")
        }
    }
}
