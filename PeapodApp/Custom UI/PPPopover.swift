//
//  PPPopover.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-24.
//

import SwiftUI

struct PPPopover<Content: View>: View {
    let hex: String
    let content: Content

    init(hex: String = "#FFFFFF", @ViewBuilder content: () -> Content) {
        self.hex = hex
        self.content = content()
    }

    var body: some View {
        let bgColor = Color(hex: hex) ?? .white

        return ZStack(alignment: .topLeading) {
            content
            
            HStack {
                Capsule()
                    .fill(Color.primary.opacity(0.15)) // Adapts to light/dark
                    .frame(width: 40, height: 6)
                    .background(.ultraThinMaterial) // Optional: if you're using a blurred background
                    .clipShape(Capsule())
            }
            .frame(maxWidth:.infinity)

//            VStack {
//                DismissReader { dismiss in
//                    Button {
//                        withAnimation { dismiss() }
//                    } label: {
//                        Label("Dismiss", systemImage: "chevron.left")
//                    }
//                    .buttonStyle(PPButton(type: .transparent, colorStyle: .monochrome, iconOnly: true))
//                }
//            }
//            .padding(.horizontal)
        }
        .navigationBarBackButtonHidden()
        .background(
            EllipticalGradient(
                stops: [
                    .init(color: bgColor, location: 0.0),
                    .init(color: Color.background, location: 1.0)
                ],
                center: .topLeading
            )
            .ignoresSafeArea()
            .opacity(0.15)
        )
        .background(Color.background)
    }
}
