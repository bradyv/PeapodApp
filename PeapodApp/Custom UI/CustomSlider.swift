//
//  ProgressView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-17.
//

import SwiftUI

struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void
    let isDraggable: Bool
    var isQQ: Bool

    @State private var layoutReady = false
    @State private var isDragging = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let sliderWidth = geometry.size.width
                let thumbSize: CGFloat = 30
                let progressWidth = cappedProgressWidth(value: value, range: range, totalWidth: sliderWidth)

                ZStack(alignment: .leading) {
                    // Background Track
                    Capsule()
                        .fill(isQQ ? Color.black.opacity(0.15) : (isDraggable ? Color.surface : Color.background.opacity(0.1)))
                        .frame(height: isDragging ? 12 : (isQQ ? 4 : 6))
                        .animation(.easeInOut(duration: 0.2), value: isDragging)

                    // Progress Track
                    Capsule()
                        .fill(isQQ ? Color.black : (isDraggable ? Color.heading : Color.background))
                        .frame(width: max(isQQ || !isDraggable ? 4 : 6, progressWidth),
                               height: isDragging ? 12 : (isQQ || !isDraggable ? 4 : 6))
                        .animation(.easeInOut(duration: 0.2), value: isDragging)

                    // Timestamp Display
                    if isDragging && isDraggable {
                        Text(formatTime(Int(value)))
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(.heading)
                            .padding(6)
                            .background(.thinMaterial)
                            .cornerRadius(5)
                            .offset(x: progressWidth - 30, y: -30)
                    }

                    // Invisible Thumb
                    Circle()
                        .fill(isDraggable ? Color.clear : Color.clear.opacity(0.1))
                        .frame(width: thumbSize, height: thumbSize)
                        .contentShape(Rectangle())
                        .offset(x: progressWidth - thumbSize / 2)
                        .gesture(
                            isDraggable
                            ? DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let newValue = min(
                                        max(range.lowerBound,
                                            range.lowerBound + (gesture.location.x / sliderWidth) * (range.upperBound - range.lowerBound)),
                                        range.upperBound
                                    )
                                    
                                    value = newValue
                                    isDragging = true
                                    onEditingChanged(true)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    onEditingChanged(false)
                                    impactFeedback.impactOccurred()
                                }
                            : nil
                        )
                }
                .frame(height: 12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            DispatchQueue.main.async {
                layoutReady = true
            }
        }
    }

    // Helper to prevent visual overflow
    private func cappedProgressWidth(value: Double, range: ClosedRange<Double>, totalWidth: CGFloat) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let ratio = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(ratio) * totalWidth
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
