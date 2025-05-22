//
//  PPSheet.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-16.
//

import SwiftUI

struct PPSheet: ViewModifier {

    func body(content: Content) -> some View {
        ZStack {
            content
                .presentationCornerRadius(32)
                .presentationDragIndicator(.visible)
                .background(Color.background)
        }
        .overlay(alignment:.top) {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 32, bottomLeading: 0, bottomTrailing: 0, topTrailing: 32)).strokeBorder(Color.white.opacity(0.25), lineWidth:1)
                .frame(height:64)
                .mask(
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                   startPoint: .top, endPoint: .bottom)
                )
        }
    }
}
