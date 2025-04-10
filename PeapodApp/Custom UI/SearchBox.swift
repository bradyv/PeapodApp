//
//  SearchBox.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct SearchBox: View {
    var body: some View {
        HStack {
            Image(systemName: "plus.magnifyingglass")
                .resizable()
                .frame(width: 12, height: 12)
                .opacity(0.35)
            
            Text("Find a podcast")
                .textBody()
        }
        .padding(.horizontal,12)
        .padding(.vertical,8)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Color.surface)
        .clipShape(Capsule())
    }
}
