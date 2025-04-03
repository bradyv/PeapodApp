//
//  SubscriptionsView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct SubscriptionsView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "isSubscribed == YES"),
        animation: .default
    ) var subscriptions: FetchedResults<Podcast>
    @State private var showPodcast: Bool = false
    @State private var selectedPodcast: Podcast? = nil
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    
    var body: some View {
        VStack(alignment:.leading) {
            Text("Subscriptions")
                .titleSerif()
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(subscriptions) { podcast in
                    KFImage(URL(string:podcast.image ?? ""))
                        .resizable()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                        .onTapGesture {
                            selectedPodcast = podcast
                        }
                }
            }
            .sheet(item: $selectedPodcast) { podcast in
                PodcastDetailView(feedUrl: podcast.feedUrl ?? "")
                    .modifier(PPSheet())
            }
        }
        .frame(maxWidth:.infinity)
        .padding()
    }
}
