//
//  PPSpinner.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-13.
//

import SwiftUI

struct PPSpinner: View {
    var color: Color = .accentColor
    var disabled: Bool = false
    var size: CGFloat? = 20
    @State private var isAnimating = false

    var body: some View {
        VStack {
            Circle()
                .trim(from: 0, to: 0.4)
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundColor(color.opacity(disabled ? 0.5 : 1))
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isAnimating)
                .frame(width: size, height: size)
                .onAppear { self.isAnimating = true }
        }
        .frame(width: 20, height: 20)
    }
}
