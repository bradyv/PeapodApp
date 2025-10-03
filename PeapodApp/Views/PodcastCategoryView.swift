//
//  PodcastCategoryView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-10-02.
//

import SwiftUI

struct PodcastCategoryView: View {
    let categoryName: String
    let genreId: Int
    
    @Environment(\.managedObjectContext) private var context
    @State private var podcasts: [PodcastResult] = []
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
    
    var body: some View {
        ScrollView {
            if podcasts.isEmpty {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(1...9, id: \.self) {_ in
                        SkeletonItem(cornerRadius:24)
                    }
                }
                .mask(
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                   startPoint: .top, endPoint: .bottom)
                )
                
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(podcasts.enumerated()), id: \.1.id) { index, podcast in
                        NavigationLink {
                            PodcastDetailView(feedUrl: podcast.feedUrl)
                        } label: {
                            ZStack(alignment:.bottomTrailing) {
                                ArtworkView(url: podcast.artworkUrl600, size: nil, cornerRadius: 24)
                                
                                if podcast.isSubscribed(in: context) {
                                    ZStack {
                                        Image(systemName:"checkmark")
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width:44,height:44)
                                    .background(Color.accentColor)
                                    .clipShape(Circle())
                                    .glassEffect(in:Circle())
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(Color.background)
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.large)
        .contentMargins(16, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onAppear {
            loadPodcasts()
        }
    }
    
    private func loadPodcasts() {
        PodcastAPI.fetchTopPodcastsByGenre(genreId: genreId, limit: 30) { fetchedPodcasts in
            DispatchQueue.main.async {
                self.podcasts = fetchedPodcasts
            }
        }
    }
}
