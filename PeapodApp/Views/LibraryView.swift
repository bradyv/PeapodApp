//
//  LibraryView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct LibraryView: View {
    @FetchRequest(fetchRequest: Podcast.subscriptionsFetchRequest(), animation: .interactiveSpring)
    var subscriptions: FetchedResults<Podcast>
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
                        PPPopover(showBg: true) {
                            LatestEpisodesView(namespace: namespace)
                        }
                    } label: {
                        RowItem(icon: "calendar", label: "Most Recent")
                    }
                    
                    NavigationLink {
                        PPPopover(showBg: true) {
                            SavedEpisodesView(namespace: namespace)
                        }
                    } label: {
                        RowItem(icon: "arrowshape.bounce.right", label: "Play Later")
                    }
                    
                    NavigationLink {
                        PPPopover(showBg: true) {
                            FavEpisodesView(namespace: namespace)
                        }
                    } label: {
                        RowItem(icon: "heart", label: "Favorites")
                    }
                }
            }
        }
        .padding(.horizontal).padding(.top,24)
        .frame(maxWidth:.infinity)
    }
}
