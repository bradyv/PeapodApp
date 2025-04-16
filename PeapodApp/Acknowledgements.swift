//
//  Acknowledgements.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-15.
//

import SwiftUI

struct Acknowledgements: View {
    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:16) {
                Text("Peapod makes use of the following open source libraries.")
                    .textBody()
                
                VStack {
                    RowItem(icon: "link", label:"ColorThief")
                    RowItem(icon: "link", label:"FeedKit")
                    RowItem(icon: "link", label:"Kingfisher")
                    RowItem(icon: "link", label:"SwiftSoup")
                }
            }
            .frame(maxWidth:.infinity,alignment:.leading)
        }
        .background(Color.background)
        .contentMargins(.horizontal,16, for: .scrollContent)
        .navigationTitle("Libraries")
        .navigationBarTitleDisplayMode(.inline)
    }
}
