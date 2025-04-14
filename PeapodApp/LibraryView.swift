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
    
    var body: some View {
        VStack(alignment:.leading) {
            
            Text("Library")
                .titleSerif()
                .frame(maxWidth:.infinity, alignment:.leading)
        
            Spacer()
            
            if !subscriptions.isEmpty {
                VStack(spacing: 8) {
                    RowItem(icon: "app.badge", label: "Latest Episodes")
                        .onTapGesture {
                            activeSheet = .latest
                        }
                    RowItem(icon: "bookmark", label: "Saved Episodes")
                        .onTapGesture {
                            activeSheet = .saved
                        }
                }
            }
        }
        .padding(.horizontal).padding(.top,24)
        .frame(maxWidth:.infinity)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .latest:
                LatestEpisodes().modifier(PPSheet())
            case .saved:
                SavedEpisodes().modifier(PPSheet())
            case .activity:
                ActivityView().modifier(PPSheet())
            }
        }
    }
}
