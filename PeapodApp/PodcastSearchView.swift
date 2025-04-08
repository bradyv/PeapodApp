//
//  PodcastSearchView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-03-31.
//

import SwiftUI
import Kingfisher

struct PodcastSearchView: View {
    @FocusState private var isTextFieldFocused: Bool
    @StateObject private var fetcher = PodcastFetcher()
    @State private var selectedPodcast: PodcastResult? = nil

    var body: some View {
        VStack {
            VStack {
                HStack {
                    Image(systemName: "plus.magnifyingglass")
                        .resizable()
                        .frame(width: 12, height: 12)
                        .opacity(0.35)
                    TextField("Find a podcast", text: $fetcher.query)
                        .focused($isTextFieldFocused)
                        .textRow()
                        .onSubmit {
                            fetcher.search()
                        }
                    
                    
                    if !fetcher.query.isEmpty {
                        Button(action: {
                            fetcher.query = ""
                            isTextFieldFocused = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.surface)
                .cornerRadius(44)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isTextFieldFocused = true
                    }
                }
            }
            .padding(.horizontal).padding(.top)
            
            if fetcher.query.isEmpty {
                ScrollView {
                    Text("Top Podcasts")
                        .headerSection()
                        .frame(maxWidth:.infinity, alignment:.leading)
                    
                    TopPodcasts()
                }
                .maskEdge(.bottom)
                .padding()
            } else {
                ScrollView {
                    ForEach(fetcher.results, id: \.id) { podcast in
                        HStack {
                            KFImage(URL(string:podcast.artworkUrl600))
                                .resizable()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.15), lineWidth: 1))
                            
                            VStack(alignment: .leading) {
                                Text(podcast.title)
                                    .titleCondensed()
                                Text(podcast.author)
                                    .textDetail()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal)
                        .onTapGesture {
                            selectedPodcast = podcast
                        }
                    }
                }
                .frame(maxWidth:.infinity)
            }
        }
        .onAppear {
            fetcher.fetchTopPodcasts()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
        .sheet(item: $selectedPodcast) { podcast in
            PodcastDetailLoaderView(feedUrl: podcast.feedUrl)
                .modifier(PPSheet())
        }
    }
}
