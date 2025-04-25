//
//  SubscriptionsView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct SubscriptionsView: View {
    @Environment(\.colorScheme) var colorScheme
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "isSubscribed == YES"),
        animation: .default
    ) var subscriptions: FetchedResults<Podcast>
    @State private var showPodcast: Bool = false
    @State private var selectedPodcast: Podcast? = nil
    @State private var showSearch = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    var namespace: Namespace.ID
    
    var body: some View {
        VStack(alignment:.leading) {
            if !subscriptions.isEmpty {
                Text("My Shows")
                    .headerSection()
            }
            
            ZStack(alignment: .topLeading) {
                // Actual grid with Add button + (possibly empty) real subscriptions
                LazyVGrid(columns: columns, spacing: 16) {
                    // Always-visible Add button
                    NavigationLink {
                        PPPopover(showDismiss: false) {
                            PodcastSearchView(namespace:namespace)
                        }
                        .navigationTransition(.zoom(sourceID: "ppsearch", in: namespace))
                    } label: {
                        VStack {
                            Image(systemName: "plus.magnifyingglass")
                            Text("Add a podcast")
                                .textDetailEmphasis()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.surface)
                        .foregroundStyle(Color.heading)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.surface, lineWidth: 1))
                        .matchedTransitionSource(id: "ppsearch", in: namespace)
                    }

                    // Real podcasts
                    if !subscriptions.isEmpty {
                        ForEach(subscriptions.sorted(by: { $1.title?.trimmedTitle() ?? "Podcast title" > $0.title?.trimmedTitle() ?? "Podcast title" })) { podcast in
                            NavigationLink {
                                PPPopover(hex: podcast.podcastTint ?? "#FFFFFF") {
                                    PodcastDetailView(feedUrl: podcast.feedUrl ?? "", namespace: namespace)
                                }
                                .navigationTransition(.zoom(sourceID: podcast.id, in: namespace))
                            } label: {
                                KFImage(URL(string: podcast.image ?? ""))
                                    .resizable()
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25), lineWidth: 1))
                                    .matchedTransitionSource(id: podcast.id, in: namespace)
                            }
                        }
                    }
                }

                // Overlayed placeholder grid, masked as a single unit
                if subscriptions.isEmpty {
                    LazyVGrid(columns: columns, spacing: 16) {
                        // Add empty placeholder to maintain grid offset (position 0)
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)

                        ForEach(0..<5, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.surface)
                                .aspectRatio(1, contentMode: .fit)
                                .opacity(0.5)
                        }
                    }
                    .mask(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false) // So the overlay doesn't block taps on the real button
                }
            }
            .sheet(item: $selectedPodcast) { podcast in
                PodcastDetailView(feedUrl: podcast.feedUrl ?? "", namespace: namespace)
                    .modifier(PPSheet())
            }
        }
        .frame(maxWidth:.infinity)
        .padding()
    }
}
