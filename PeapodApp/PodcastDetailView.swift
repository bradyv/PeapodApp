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
        VStack {
            if let podcast {
                if showSearch {
                    VStack(alignment:.leading) {
                        
                        PodcastEpisodeSearchView(podcast: podcast, showSearch: $showSearch, selectedEpisode: $selectedEpisode)
                        
                    }
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        )
                    )
                    .padding()
                } else {
                    ZStack {
                        ScrollView {
                            VStack {
                                Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
                                    .textBody()
                                    .lineLimit(showFullDescription ? nil :  3)
                                    .frame(maxWidth:.infinity, alignment:.leading)
                                    .onTapGesture {
                                        withAnimation {
                                            showFullDescription.toggle()
                                        }
                                        print(showFullDescription)
                                    }
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .animation(.easeOut(duration: 0.15), value: showFullDescription)
                                
                                Spacer().frame(height:24)
                                
                                LazyVStack(alignment: .leading) {
                                    if let latestEpisode = episodes.first {
                                        Text("Latest Episode")
                                            .headerSection()
                                        
                                        EpisodeItem(episode: latestEpisode)
                                            .lineLimit(3)
                                            .padding(.bottom, 24)
                                            .onTapGesture {
                                                selectedEpisode = latestEpisode
                                            }
                                    }
                                    
                                    let remainingEpisodes = Array(episodes.dropFirst())
                                    
                                    if !remainingEpisodes.isEmpty {
                                        Text("Episodes")
                                            .headerSection()
                                        
                                        ForEach(remainingEpisodes, id: \.id) { episode in
                                            EpisodeItem(episode: episode)
                                                .lineLimit(3)
                                                .padding(.bottom, 24)
                                                .onTapGesture {
                                                    selectedEpisode = episode
                                                }
                                        }
                                    }
                                }
                                .sheet(item: $selectedEpisode) { episode in
                                    EpisodeView(episode: episode)
                                        .modifier(PPSheet())
                                }
                            }
                            .padding(.top,52)
                            .padding()
                        }
                        .maskEdge(.top)
                        .maskEdge(.bottom)
                        .padding(.top,88)
                        
                        VStack {
                            HStack(alignment:.top) {
                                KFImage(URL(string:podcast.image ?? ""))
                                    .resizable()
                                    .frame(width: 128, height: 128)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                                    .shadow(color:
                                                (Color(hex: podcast.podcastTint)?.opacity(0.45))
                                            ?? Color.black.opacity(0.35),
                                            radius: 128
                                    )
                                
                                Spacer()
                                
                                Button(action: {
                                    showSearch.toggle()
                                }) {
                                    Label("Search \(podcast.title ?? "episodes"))", systemImage: "text.magnifyingglass")
                                }
                                .buttonStyle(PPButton(type: .transparent, colorStyle: .monochrome, iconOnly: true))
                                
                                Button(action: {
                                    podcast.isSubscribed.toggle()
                                    
                                    if podcast.isSubscribed,
                                       let latest = (podcast.episode?.array as? [Episode])?
                                        .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) })
                                        .first {
                                        latest.isQueued = true
                                    }
                                    
                                    try? podcast.managedObjectContext?.save()
                                }) {
                                    Text(podcast.isSubscribed ? "Unfollow" : "Follow")
                                }
                                .buttonStyle(PPButton(type:podcast.isSubscribed ? .transparent : .filled, colorStyle:podcast.isSubscribed ? .tinted : .monochrome))
                            }
                            Spacer()
                        }
                        .padding()
                    }
                    .transition(.opacity)
                    .frame(maxWidth:.infinity)
                    .ignoresSafeArea(edges: .all)
                    .onAppear {
                        episodes = (podcast.episode?.array as? [Episode])?.sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) }) ?? []
                        
                        Task.detached(priority: .background) {
                            await ColorTintManager.applyTintIfNeeded(to: podcast, in: context)
                            
                            await EpisodeRefresher.refreshPodcastEpisodes(for: podcast, context: context) {
                                DispatchQueue.main.async {
                                    episodes = (podcast.episode?.array as? [Episode])?.sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) }) ?? []
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(.interactiveSpring(duration: 0.25), value: showSearch)
    }
}
