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
    
    var body: some View {
        KFImage(URL(string:url))
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .ifLet(size) { view, size in
                view.frame(width: size, height: size)
            }
            .clipShape(RoundedRectangle(cornerRadius:cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.white.blendMode(.overlay), lineWidth: 1))
            .rotationEffect(.degrees(tilt ? 2 : 0))
    }
}
