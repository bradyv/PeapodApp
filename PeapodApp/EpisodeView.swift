//
//  EpisodeView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher

struct EpisodeView: View {
    @Environment(\.managedObjectContext) private var context
    let episode: Episode
    
    var body: some View {
        ZStack(alignment:.topLeading) {
            ScrollView {
                Spacer().frame(height:152)
                EpisodeItem(episode: episode)
            }
            .maskEdge(.top)
            
            VStack {
                KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                    .resizable()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                Spacer()
            }
        }
        .frame(maxWidth:.infinity)
        .padding()
    }
}
