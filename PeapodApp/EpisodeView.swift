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
        VStack(alignment:.leading) {
            Text(episode.episodeTint ?? "No episode tint")
            Text(episode.podcast?.podcastTint ?? "No podcast tint")
            KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                .resizable()
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
            
            EpisodeItem(episode: episode)
        }
        .frame(maxWidth:.infinity)
        .padding()
    }
}
