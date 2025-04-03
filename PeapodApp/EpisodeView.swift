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
    @ObservedObject var episode: Episode
    
    var body: some View {
        ZStack(alignment:.topLeading) {
            ScrollView {
                Spacer().frame(height:76)
                EpisodeItem(episode: episode, displayedFullscreen:true)
            }
            .maskEdge(.top)
            .padding(.top,76)
            
            VStack {
                Spacer()
                
                VStack {
                    Rectangle()
                        .frame(maxWidth:.infinity)
                        .frame(height:6)
                        .foregroundStyle(Color.surface)
                        .clipShape(Capsule())
                    
                    HStack {
                        Text("0.00")
                        Spacer()
                        Text("-\(countdown(seconds:Int(episode.duration)))")
                    }
                    .fontDesign(.monospaced)
                    .font(.caption)
                    
                    HStack {
                        AirPlayButton()
                            .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted, iconOnly: true))
                        Spacer()
                        Button(action: {
                            episode.isSaved.toggle()
                            try? episode.managedObjectContext?.save()
                        }) {
                            Label(episode.isSaved ? "Remove from starred" : "Star episode", systemImage: episode.isSaved ? "star.fill" : "star")
                        }
                        .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted, iconOnly: true))
                    }
                }
                .padding(.top,72)
                .background(Color.background)
                .maskEdge(.top)
            }
            
            VStack {
                KFImage(URL(string:episode.episodeImage ?? episode.podcast?.image ?? ""))
                    .resizable()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                    .shadow(color:
                        (Color(hex: episode.episodeTint)?.opacity(0.5))
                        ?? (Color(hex: episode.podcast?.podcastTint)?.opacity(0.5))
                        ?? Color.black.opacity(0.5),
                        radius: 32
                    )
                
                Spacer()
            }
        }
        .frame(maxWidth:.infinity)
        .padding()
    }
}
