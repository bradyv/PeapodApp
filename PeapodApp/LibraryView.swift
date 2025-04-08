//
//  LibraryView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct LibraryView: View {
    @State private var showSearch = false
    @State private var showSaved = false
    @State private var showLatest = false
    
    var body: some View {
        VStack(alignment:.leading) {
            
            HStack {
                Text("Library")
                    .titleSerif()
                
                Spacer()
                
//                Button(action: {
//                    showSearch.toggle()
//                    print("Open search")
//                }) {
//                    Image(systemName: "plus.magnifyingglass")
//                }
//                .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted, iconOnly: true))
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "app.badge")
                        .frame(width: 24, alignment: .center)
                        .textBody()
                    Text("Latest Episodes")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textRow()
                    Image(systemName: "chevron.right")
                        .frame(width: 16, alignment: .trailing)
                        .textBody()
                }
                .onTapGesture {
                    showLatest.toggle()
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    Image(systemName: "star")
                        .frame(width: 24, alignment: .center)
                        .textBody()
                    Text("Starred Episodes")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textRow()
                    Image(systemName: "chevron.right")
                        .frame(width: 16, alignment: .trailing)
                        .textBody()
                }
                .onTapGesture {
                    showSaved.toggle()
                }
                
                
                Divider()
            }
        }
        .padding(.horizontal).padding(.top,24)
        .frame(maxWidth:.infinity)
        .sheet(isPresented: $showSaved) {
            SavedEpisodes()
                .modifier(PPSheet())
        }
        .sheet(isPresented: $showLatest) {
            LatestEpisodes()
                .modifier(PPSheet())
        }
    }
}
