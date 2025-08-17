//
//  ImageShrinker.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-10.
//

import SwiftUI

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func trackScrollOffset(_ coordinateSpace: String, _ onChange: @escaping (CGFloat) -> Void) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named(coordinateSpace)).minY)
            }
        )
        .onPreferenceChange(ScrollOffsetPreferenceKey.self, perform: onChange)
    }
}
