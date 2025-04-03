//
//  ScrollFade.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-25.
//

import SwiftUI

struct ScrollMask: View {
    let isTop: Bool

    var body: some View {
        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: UnitPoint(x: 0.5, y: isTop ? 0 : 1), endPoint: UnitPoint(x: 0.5, y: isTop ? 1 : 0))
            .frame(height: isTop ? 24 : 64)
            .frame(maxWidth: .infinity)
            .blendMode(.destinationOut)
    }
}

struct ScrollMaskModifier: ViewModifier {
    let edge: Edge

    func body(content: Content) -> some View {
        content
            .mask {
                Rectangle()
                    .overlay(alignment: alignment(for: edge)) {
                        ScrollMask(isTop: edge == .top)
                    }
            }
    }

    private func alignment(for edge: Edge) -> Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}

extension View {
    func maskEdge(_ edge: Edge) -> some View {
        self.modifier(ScrollMaskModifier(edge: edge))
    }
}
