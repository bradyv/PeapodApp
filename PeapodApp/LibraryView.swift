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
    
    @State private var showSearch = false
    @State private var activeSheet: ActiveSheet?
    
    var body: some View {
        VStack(alignment:.leading) {
            
            Text("Library")
                .titleSerif()
                .frame(maxWidth:.infinity, alignment:.leading)
        
            Spacer()
            
            if !subscriptions.isEmpty {
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "app.badge")
                            .frame(width: 24, alignment: .center)
                            .textBody()
                        Text("Latest Episodes")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textBody()
                        Image(systemName: "chevron.right")
                            .frame(width: 16, alignment: .trailing)
                            .textBody()
                            .opacity(0.25)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeSheet = .latest
                    }
                    
                    Divider()
                    
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "star")
                            .frame(width: 24, alignment: .center)
                            .textBody()
                        Text("Starred Episodes")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textBody()
                        Image(systemName: "chevron.right")
                            .frame(width: 16, alignment: .trailing)
                            .textBody()
                            .opacity(0.25)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeSheet = .saved
                    }
                    
                    
                    Divider()
                    
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                            .frame(width: 24, alignment: .center)
                            .textBody()
                        Text("My Activity")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textBody()
                        Image(systemName: "chevron.right")
                            .frame(width: 16, alignment: .trailing)
                            .textBody()
                            .opacity(0.25)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeSheet = .activity
                    }
                    
                    
                    Divider()
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
