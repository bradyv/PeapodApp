//
//  Floating.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-28.
//

import SwiftUI

struct FloatingAnimation: ViewModifier {
    @State private var floatUp = false

    func body(content: Content) -> some View {
        content
            .offset(y: floatUp ? -6 : 6)
            .animation(
                .easeInOut(duration: 3).repeatForever(autoreverses: true),
                value: floatUp
            )
            .onAppear {
                floatUp = true
            }
    }
}

extension View {
    func floating() -> some View {
        self.modifier(FloatingAnimation())
    }
}
