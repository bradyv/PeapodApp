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
    @State private var animateGlare = false
    var showGlare: Bool = false
    
    var body: some View {
        let opacity: Double = animateGlare ? 0.3 : 0
        
        KFImage(URL(string:url))
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius:cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25), lineWidth: 1))
            .if(showGlare, transform: {
                $0.overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(opacity), Color.white.opacity(0)]),
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .animation(.easeOut(duration: 0.3), value: animateGlare)
                )
            })
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.animateGlare = true
                }
            }
    }
}
