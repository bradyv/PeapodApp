//
//  FadeInView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-09.
//

import SwiftUI

struct FadeInView<Content: View>: View {
    let delay: Double
    let content: Content
    
    @State private var isVisible = false

    init(delay: Double, @ViewBuilder content: () -> Content) {
        self.delay = delay
        self.content = content()
    }

    var body: some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .animation(.easeOut(duration: 0.3).delay(delay), value: isVisible)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isVisible = true
                }
            }
    }
}
