//
//  ScrollFade.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-25.
//

import SwiftUI
import SmoothGradient

struct ScrollMask: View {
    let edge: Edge

    var body: some View {
        SmoothLinearGradient(
            from: .black,
            to: .black.opacity(0),
            startPoint: gradientStartPoint(for: edge),
            endPoint: gradientEndPoint(for: edge),
            curve: .easeInOut
        )
        .frame(
            width: edge.isHorizontal ? 32 : nil,
            height: edge.isHorizontal ? nil : 96
        )
        .frame(maxWidth: edge.isHorizontal ? nil : .infinity,
               maxHeight: edge.isHorizontal ? .infinity : nil)
        .blendMode(.destinationOut)
    }

    private func gradientStartPoint(for edge: Edge) -> UnitPoint {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    private func gradientEndPoint(for edge: Edge) -> UnitPoint {
        switch edge {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }
}

struct ScrollMaskModifier: ViewModifier {
    let edge: Edge

    func body(content: Content) -> some View {
        content.mask {
            Rectangle()
                .overlay(alignment: alignment(for: edge)) {
                    ScrollMask(edge: edge)
                }
                .ignoresSafeArea(.all)
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

private extension Edge {
    var isHorizontal: Bool {
        self == .leading || self == .trailing
    }
}
