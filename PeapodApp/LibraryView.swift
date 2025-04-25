//
//  LibraryView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct LibraryView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.title)],
        predicate: NSPredicate(format: "isSubscribed == YES"),
        animation: .default
    ) var subscriptions: FetchedResults<Podcast>
    @State private var activeSheet: ActiveSheet?
    var namespace: Namespace.ID
    
    var body: some View {
        VStack(alignment:.leading) {
            
            Text("Library")
                .titleSerif()
                .frame(maxWidth:.infinity, alignment:.leading)
        
            Spacer()
            
            if !subscriptions.isEmpty {
                VStack(spacing: 8) {
                    NavigationLink {
                        PPPopover {
                            LatestEpisodes(namespace: namespace)
                        }
                        .navigationTransition(.zoom(sourceID: 22, in: namespace))
                    } label: {
                        RowItem(icon: "app.badge", label: "Unplayed Episodes")
                            .matchedTransitionSource(id: 22, in: namespace)
                    }
                    
                    NavigationLink {
                        PPPopover {
                            SavedEpisodes(namespace: namespace)
                        }
                        .navigationTransition(.zoom(sourceID: 33, in: namespace))
                    } label: {
                        RowItem(icon: "bookmark", label: "Saved Episodes")
                            .matchedTransitionSource(id: 33, in: namespace)
                    }
                }
            }
        }
        .padding(.horizontal).padding(.top,24)
        .frame(maxWidth:.infinity)
    }
}
