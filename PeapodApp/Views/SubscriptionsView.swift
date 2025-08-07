//
//  SubscriptionsView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct SubscriptionsView: View {
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest(), animation: .none)
    var subscriptions: FetchedResults<Podcast>
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    @State private var selectedPodcast: Podcast? = nil
    var namespace: Namespace.ID
    
    var body: some View {
        VStack(alignment:.leading) {
            Text("Following")
                .titleSerifMini()
            
            ZStack(alignment: .topLeading) {
                // Actual grid with Add button + (possibly empty) real subscriptions
                LazyVGrid(columns: columns, spacing: 16) {
                    // Always-visible Add button
//                    NavigationLink {
//                        PPPopover(showDismiss: false, pushView: false) {
//                            PodcastSearchView(namespace:namespace)
//                        }
//                        .navigationTransition(.zoom(sourceID: "ppsearch", in: namespace))
//                    } label: {
//                        VStack {
//                            Image(systemName: "plus.magnifyingglass")
//                                .symbolRenderingMode(.hierarchical)
//                            Text("Add a podcast")
//                                .textDetailEmphasis()
//                        }
//                        .frame(maxWidth: .infinity, maxHeight: .infinity)
//                        .aspectRatio(1, contentMode: .fit)
//                        .background(Color.surface)
//                        .foregroundStyle(Color.heading)
//                        .clipShape(RoundedRectangle(cornerRadius: 16))
//                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.surface, lineWidth: 1))
//                        .matchedTransitionSource(id: "ppsearch", in: namespace)
//                    }

                    // Real podcasts - optimized for scroll performance
                    if !subscriptions.isEmpty {
                        ForEach(subscriptions, id: \.objectID) { podcast in
                            PodcastGridItem(podcast: podcast) {
                                selectedPodcast = podcast
                            }
                        }
                    }
                }

                // Overlayed placeholder grid, masked as a single unit
                if subscriptions.isEmpty {
                    LazyVGrid(columns: columns, spacing: 16) {
                        // Add empty placeholder to maintain grid offset (position 0)
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.surface)
                                .aspectRatio(1, contentMode: .fit)
                                .opacity(0.5)
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.surface.opacity(0.5), lineWidth: 1))
                        }
                    }
                    .mask(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false) // So the overlay doesn't block taps on the real button
                    
                    VStack {
                        Spacer()
                        Text("Library is empty")
                            .titleCondensed()
                        
                        Text("Follow some podcasts to get started.")
                            .textBody()
                        Spacer()
                    }
                    .frame(maxWidth:.infinity)
                }
            }
        }
        .frame(maxWidth:.infinity)
        .padding()
        .sheet(item: $selectedPodcast) { podcast in
            PodcastDetailView(feedUrl: podcast.feedUrl ?? "", namespace:namespace)
                .modifier(PPSheet())
        }
    }
}

// MARK: - Optimized Podcast Grid Item for Scroll Performance
struct PodcastGridItem: View {
    let podcast: Podcast
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            KFImage(URL(string: podcast.image ?? ""))
                .placeholder {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.surface)
                }
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.blendMode(.overlay), lineWidth: 1.5))
        }
        .buttonStyle(PlainButtonStyle())
        .drawingGroup() // Render as single composited layer
    }
}
