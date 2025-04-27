//
//  PPPopover.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-24.
//

import SwiftUI

private struct ShowDismissKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var showDismissBinding: Binding<Bool>? {
        get { self[ShowDismissKey.self] }
        set { self[ShowDismissKey.self] = newValue }
    }
}

struct PPPopover<Content: View>: View {
    let hex: String
    let content: Content
    @State private var internalShowDismiss: Bool
    @State private var pushView: Bool
    @State private var animateBg: Bool

    init(hex: String = "#FFFFFF", showDismiss: Bool = true, pushView: Bool = true, animateBg: Bool = false, @ViewBuilder content: () -> Content) {
        self.hex = hex
        self._internalShowDismiss = State(initialValue: showDismiss)
        self.pushView = pushView
        self.content = content()
        self.animateBg = false
    }

    var body: some View {
        let bgColor = Color(hex: hex) ?? .white

        return
            ZStack(alignment: .topLeading) {
            content
                .environment(\.showDismissBinding, $internalShowDismiss)
            
            if internalShowDismiss {
                if pushView {
                    HStack {
                        DismissReader { dismiss in
                            Button {
                                withAnimation { animateBg = false; dismiss() }
                            } label: {
                                Label("Dismiss", systemImage: "chevron.left")
                            }
                            .buttonStyle(ShadowButton(iconOnly: true))
                        }
                    }
                    .padding(.horizontal)
                } else {
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
        }
        .navigationBarBackButtonHidden()
        .if(pushView, transform: {
            $0.toolbarBackground(.hidden, for: .navigationBar)
        })
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    animateBg = true
                }
            }
        }
        .background(
            EllipticalGradient(
                stops: [
                    .init(color: bgColor, location: 0.0),
                    .init(color: Color.background, location: 1.0)
                ],
                center: .topLeading
            )
            .ignoresSafeArea()
            .opacity(animateBg ? 0.15 : 0)
        )
        .background(Color.background)
    }
}
