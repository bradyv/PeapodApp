//
//  PPSheet.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-16.
//

import SwiftUI

struct PPSheet: ViewModifier {
    let hasBackground: Bool
    
    init(bg: Bool = false) {
        self.hasBackground = bg
    }

    func body(content: Content) -> some View {
        content
            .presentationCornerRadius(32)
            .presentationDragIndicator(.hidden)
            .presentationDetents([.medium, .large]) 
            .background(
                hasBackground ? nil : EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color.surface, location: 0.00),
                        Gradient.Stop(color: Color.background, location: 1.00)
                    ],
                    center: UnitPoint(x: 0, y: 0)
                )
            )
            .background(Color.background)
    }
}
