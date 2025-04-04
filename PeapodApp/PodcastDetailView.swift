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
        if let podcast {
            ZStack {
                ScrollView {
                    Spacer().frame(height:64)
                    VStack(alignment: .leading, spacing:8) {
                        Text(podcast.title ?? "Podcast Title")
                            .titleSerif()
                        
                        Text(parseHtml(podcast.podcastDescription ?? "Podcast description"))
                            .textBody()
                            .lineLimit(3)
                    }
                    .frame(maxWidth:.infinity, alignment:.leading)
                    
                    LazyVStack(alignment: .leading) {
                        ForEach(episodes, id: \.id) { episode in
                            EpisodeItem(episode: episode)
                                .lineLimit(3)
                                .padding(.bottom, 24)
                                .onTapGesture {
                                    selectedEpisode = episode
                                }
                        }
                    }
                    .sheet(item: $selectedEpisode) { episode in
                        EpisodeView(episode: episode)
                            .modifier(PPSheet())
                    }
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
                                        (Color(hex: podcast.podcastTint)?.opacity(0.35))
                                    ?? Color.black.opacity(0.35),
                                    radius: 32
                            )
                        
                        Spacer()
                        
                        Button(action: {
                            podcast.isSubscribed.toggle()
                            try? podcast.managedObjectContext?.save()
                        }) {
                            Text(podcast.isSubscribed ? "Unfollow" : "Follow")
                        }
                        .buttonStyle(PPButton(
                            type:.filled,
                            colorStyle:.monochrome,
                            customColors: ButtonCustomColors(
                                foreground: .white,
                                background: Color(hex: podcast.podcastTint) ?? .black
                            )
                        ))
                    }
                    Spacer()
                }
            }
            .frame(maxWidth:.infinity)
            .padding()
            .ignoresSafeArea(edges: .all)
            .onAppear {
                episodes = (podcast.episode?.array as? [Episode]) ?? []

                Task.detached(priority: .background) {
                    ColorTintManager.applyTintIfNeeded(to: podcast, in: context)
                }
            }
        }
    }
}
