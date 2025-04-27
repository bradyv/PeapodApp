//
//  PPSheet.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-16.
//

import SwiftUI

struct PPSheet: ViewModifier {
    let hasBackground: Bool
    let shortStack: Bool
    let showOverlay: Bool
    
    init(bg: Bool = false, shortStack: Bool = false, showOverlay: Bool = true) {
        self.hasBackground = bg
        self.shortStack = shortStack
        self.showOverlay = showOverlay
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .presentationCornerRadius(32)
                .background(
                    hasBackground ? nil : EllipticalGradient(
                        stops: [
                            Gradient.Stop(color: Color.surface, location: 0.00),
                            Gradient.Stop(color: Color.background, location: 1.00)
                        ],
                        center: UnitPoint(x: 0, y: 0)
                    )
                    .ignoresSafeArea(edges:.top)
                )
                .background(Color.background)
        }
    }
}

enum ActiveSheet: Identifiable {
    case latest, saved, activity

    var id: Int {
        switch self {
        case .latest: return 0
        case .saved: return 1
        case .activity: return 2
        }
    }
}
