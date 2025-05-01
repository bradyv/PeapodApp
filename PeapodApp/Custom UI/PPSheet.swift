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
    }
}
