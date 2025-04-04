//
//  LibraryView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct LibraryView: View {
    @State private var showSearch = false
    
    var body: some View {
        VStack(alignment:.leading) {
            
            HStack {
                Text("Library")
                    .titleSerif()
                
                Spacer()
                
                Button(action: {
                    showSearch.toggle()
                    print("Open search")
                }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted, iconOnly: true))
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
                
                Divider()
            }
        }
        .padding(.horizontal)
        .frame(maxWidth:.infinity)
        .sheet(isPresented: $showSearch) {
            PodcastSearchView()
                .modifier(PPSheet())
        }
    }
}
