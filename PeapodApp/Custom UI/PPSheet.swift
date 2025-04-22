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
    @Binding var dismissTrigger: Bool
    @Binding var detent: PresentationDetent
    
    init(bg: Bool = false, shortStack: Bool = false,dismissTrigger: Binding<Bool> = .constant(false), showOverlay: Bool = true, detent: Binding<PresentationDetent> = .constant(.large)) {
        self.hasBackground = bg
        self.shortStack = shortStack
        self.showOverlay = showOverlay
        self._dismissTrigger = dismissTrigger
        self._detent = detent
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .presentationCornerRadius(32)
                .presentationDetents(shortStack ? [.medium, .large] : [.large], selection: $detent)
                .presentationContentInteraction(.resizes)
                .interactiveDismissDisabled(false)
                .presentationDragIndicator(.hidden)
                .onChange(of: detent) { newValue in
                    if shortStack && newValue == .medium {
                        dismissTrigger = true
                    }
                }
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
            if showOverlay {
                NowPlaying()
            }
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
