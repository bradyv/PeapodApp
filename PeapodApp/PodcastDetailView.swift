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
    @Environment(\.managedObjectContext) private var context
    @FetchRequest var podcastResults: FetchedResults<Podcast>
    @State private var episodes: [Episode] = []
    @State private var selectedEpisode: Episode? = nil
    @State var showFullDescription: Bool = false
    @State private var showSearch = false
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedDetent: PresentationDetent = .medium
    var podcast: Podcast? { podcastResults.first }

    init(feedUrl: String) {
        _podcastResults = FetchRequest<Podcast>(
            entity: Podcast.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "feedUrl == %@", feedUrl),
            animation: .default
        )
    }

    var body: some View {
        FadeInView(delay: 0.2) {
            VStack {
                if let podcast {
                    if showSearch {
                        VStack(alignment:.leading) {
                            PodcastEpisodeSearchView(podcast: podcast, showSearch: $showSearch, selectedEpisode: $selectedEpisode)
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
                                Spacer().frame(height:52)
                                Color.clear
                                    .frame(height: 1)
                                    .trackScrollOffset("scroll") { value in
                                        scrollOffset = value
                                    }
                                
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
                                            EpisodeItem(episode: latestEpisode)
                                                .lineLimit(3)
                                                .padding(.bottom, 24)
                                                .onTapGesture {
                                                    selectedEpisode = latestEpisode
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
                                                    EpisodeItem(episode: episode)
                                                        .lineLimit(3)
                                                        .padding(.bottom, 24)
                                                        .onTapGesture {
                                                            selectedEpisode = episode
                                                        }
                                                }
                                            }
                                        }
                                    }
                                }
                                .sheet(item: $selectedEpisode) { episode in
                                    EpisodeView(episode: episode, selectedDetent: $selectedDetent)
                                        .modifier(PPSheet(shortStack: true))
                                        .presentationDetents([.medium, .large], selection: $selectedDetent)
                                        .presentationContentInteraction(.resizes)
                                }
                            }
                            .coordinateSpace(name: "scroll")
                            .contentMargins(16, for: .scrollContent)
                            .maskEdge(.top)
                            .maskEdge(.bottom)
                            .padding(.top,88)
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
                            
                            VStack {
                                let minSize: CGFloat = 64
                                let maxSize: CGFloat = 128
                                let threshold: CGFloat = 72
                                let shrink = max(minSize, min(maxSize, maxSize + min(0, scrollOffset - threshold)))
                                
                                HStack(alignment:.top) {
                                    KFImage(URL(string: podcast.image ?? ""))
                                        .resizable()
                                        .frame(width: shrink, height: shrink)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                                        .shadow(color:Color.tint(for:podcast),
                                                radius: 128
                                        )
                                        .animation(.easeOut(duration: 0.1), value: shrink)
                                    
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
                            .padding()
                        }
                    }
                }
            }
            .ignoresSafeArea(.all)
            .animation(.interactiveSpring(duration: 0.25), value: showSearch)
        }
    }
}
