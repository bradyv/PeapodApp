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
    var showDismiss: Bool = true

    init(hex: String = "#FFFFFF", showDismiss: Bool = true, @ViewBuilder content: () -> Content) {
        self.hex = hex
        self.showDismiss = showDismiss
        self.content = content()
    }

    var body: some View {
        let bgColor = Color(hex: hex) ?? .white

        return ZStack(alignment: .topTrailing) {
            content
            
            if showDismiss {
//                HStack {
//                    DismissReader { dismiss in
//                        Button {
//                            withAnimation { dismiss() }
//                        } label: {
//                            Label("Dismiss", systemImage: "chevron.down")
//                        }
//                        .buttonStyle(ShadowButton(iconOnly: true))
//                    }
//                }
//                .padding(.horizontal)
                
                HStack {
                    Capsule()
                        .fill(Color.primary.opacity(0.15)) // Adapts to light/dark
                        .frame(width: 40, height: 6)
                        .background(.ultraThinMaterial) // Optional: if you're using a blurred background
                        .clipShape(Capsule())
                }
                .frame(maxWidth:.infinity)
            }
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
