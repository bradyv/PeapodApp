//
//  ArtworkView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-04.
//

import SwiftUI
import Kingfisher

struct ArtworkView: View {
    @Environment(\.colorScheme) var colorScheme
    let url: String
    let size: CGFloat
    let cornerRadius: CGFloat
    
    var body: some View {
        KFImage(URL(string:url))
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius:cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25), lineWidth: 1))
    }
}
