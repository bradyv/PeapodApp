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
    let size: CGFloat?
    let cornerRadius: CGFloat
    var tilt: Bool = false
    
    var body: some View {
        KFImage(URL(string:url))
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .ifLet(size) { view, size in
                view.frame(width: size, height: size)
            }
            .clipShape(RoundedRectangle(cornerRadius:cornerRadius))
            .if(tilt, transform: { $0.overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.white.blendMode(.overlay), lineWidth: 1.5)) })
            .if(!tilt, transform: { $0.glassEffect(in: .rect(cornerRadius: cornerRadius)) })
            .rotationEffect(.degrees(tilt ? 2 : 0))
    }
}
