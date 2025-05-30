//
//  Acknowledgements.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-15.
//

import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.openURL) var openURL
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:52)
            Text("Libraries")
                .titleSerif()
                .frame(maxWidth:.infinity, alignment:.leading)
                .padding(.bottom,24)
            
            VStack(alignment:.leading, spacing:16) {
                Text("Peapod makes use of the following open source libraries.")
                    .textBody()
                
                VStack {
                    RowItem(icon: "link", label:"ColorThiefSwift")
                        .onTapGesture {
                            if let url = URL(string: "https://github.com/yamoridon/ColorThiefSwift") {
                                openURL(url)
                            }
                        }
                    RowItem(icon: "link", label:"FeedKit")
                        .onTapGesture {
                            if let url = URL(string: "https://github.com/nmdias/FeedKit") {
                                openURL(url)
                            }
                        }
                    RowItem(icon: "link", label:"Kingfisher")
                        .onTapGesture {
                            if let url = URL(string: "https://github.com/onevcat/Kingfisher") {
                                openURL(url)
                            }
                        }
                    RowItem(icon: "link", label:"Rive")
                        .onTapGesture {
                            if let url = URL(string: "https://github.com/rive-app/rive-ios") {
                                openURL(url)
                            }
                        }
                    RowItem(icon: "link", label:"SwiftSoup")
                        .onTapGesture {
                            if let url = URL(string: "https://github.com/scinfu/SwiftSoup") {
                                openURL(url)
                            }
                        }
                }
            }
            .frame(maxWidth:.infinity,alignment:.leading)
        }
        .maskEdge(.top)
        .maskEdge(.bottom)
        .contentMargins(.horizontal,16, for: .scrollContent)
    }
}
