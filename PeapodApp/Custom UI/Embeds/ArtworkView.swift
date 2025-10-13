//
//  ArtworkView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-04.
//

import SwiftUI
import Kingfisher

struct ArtworkView: View {
    let url: String
    var size: CGFloat?
    let cornerRadius: CGFloat
    var tilt: Bool = false
    
    // Cache the URL parsing
    private var imageURL: URL? {
        URL(string: url)
    }
    
    var body: some View {
        Group {
            if let imageURL = imageURL {
                KFImage(imageURL)
                    .placeholder {
                        Image("placeholder")
                            .resizable()
                            .aspectRatio(1, contentMode:.fill)
                    }
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                Image("placeholder")
                    .resizable()
                    .aspectRatio(1, contentMode:.fill)
            }
        }
        .ifLet(size) { view, size in
            view.frame(width: size, height: size)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.white.blendMode(.overlay), lineWidth: 1)
        )
        .rotationEffect(.degrees(tilt ? 2 : 0))
        .drawingGroup()
    }
}
