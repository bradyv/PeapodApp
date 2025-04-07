//
//  Welcome.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-06.
//

import SwiftUI
import Kingfisher

//struct Welcome: View {
//    @Environment(\.managedObjectContext) private var context
//    @State private var topPodcasts: [PodcastResult] = []
//    @State private var selectedPodcast: PodcastResult? = nil
//    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
//    
//    var body: some View {
//        LazyVGrid(columns: columns, spacing: 16) {
//            ForEach(topPodcasts, id: \.id) { podcast in
//                VStack {
//                    KFImage(URL(string: podcast.artworkUrl600))
//                        .resizable()
//                        .aspectRatio(1, contentMode: .fit)
//                        .clipShape(RoundedRectangle(cornerRadius: 16))
//                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
//                }
//                .onTapGesture {
//                    podcast.isSubscribed.toggle()
//                    try? podcast.managedObjectContext?.save()
//                }
//            }
//        }
//    }
//}
