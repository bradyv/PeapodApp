//
//  Toast.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-28.
//

import SwiftUI

struct Toast: View {
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(message)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThickMaterial)
        .foregroundStyle(Color.heading)
        .clipShape(Capsule())
        .textDetail()
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .overlay(
            Capsule()
                .inset(by: 0.5)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
        )
        .overlay(
            Capsule()
                .inset(by: 1)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

class ToastManager: ObservableObject {
    @Published var message: String? = nil
    @Published var icon: String? = nil

    func show(message: String, icon: String = "checkmark.circle", duration: TimeInterval = 2.0) {
        // Trigger haptic immediately
        let feedbackType: UINotificationFeedbackGenerator.FeedbackType = {
            switch icon {
            case "sparkles": return .success
            case "checkmark.circle": return .success
            case "xmark.circle": return .error
            case "exclamationmark.triangle": return .warning
            default: return .success
            }
        }()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(feedbackType)

        // Show toast
        withAnimation(.easeInOut(duration: 0.3)) {
            self.message = message
            self.icon = icon
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.message = nil
                self.icon = nil
            }
        }
    }
}

struct ToastModifier: ViewModifier {
    @EnvironmentObject var toastManager: ToastManager

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                Group {
                    if let message = toastManager.message,
                       let icon = toastManager.icon {
                        Toast(message: message, icon: icon)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
    }
}

extension View {
    func toast() -> some View {
        self.modifier(ToastModifier())
    }
}
