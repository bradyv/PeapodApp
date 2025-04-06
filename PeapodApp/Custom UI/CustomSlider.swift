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
    let isDraggable: Bool // New property to enable/disable dragging
    var isQQ: Bool
    
    @State private var layoutReady = false
    @State private var isDragging = false // Track dragging state
    
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let sliderWidth = geometry.size.width
                let thumbSize: CGFloat = 30
                
                ZStack(alignment: .leading) {
                    // Background Track (Dynamic Height)
                    Capsule()
                        .fill(isQQ ? Color.black.opacity(0.15) : (isDraggable ? Color.surface : Color.background.opacity(0.1)))
                        .frame(height: isDragging ? 12 : (isQQ ? 4 : 6))
                        .animation(.easeInOut(duration: 0.2), value: isDragging)
                    
                    if layoutReady {
                        // Progress Track (Dynamic Height)
                        Capsule()
                            .fill(isQQ ? Color.black : (isDraggable ? Color.heading : Color.background))
                            .frame(width: isQQ || !isDraggable ? max(3, CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * sliderWidth) : CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * sliderWidth, height: isDragging ? 12 : (isQQ || !isDraggable ? 4 : 6))
                            .animation(.easeInOut(duration: 0.2), value: isDragging)
                    }
                    
                    // Timestamp Display Above Thumb (Only show if draggable)
                    if isDragging && isDraggable {
                        Text(formatTime(Int(value)))
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(.heading)
                            .padding(6)
                            .background(.thinMaterial)
                            .cornerRadius(5)
                            .offset(x: CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * sliderWidth - 60 / 2, y: -30)
                    }
                    
                    // Invisible Draggable Thumb (Only works if `isDraggable` is true)
                    Circle()
                        .fill(isDraggable ? Color.clear : Color.clear.opacity(0.1))// Gray out when disabled
                        .frame(width: thumbSize, height: thumbSize)
                        .contentShape(Rectangle()) // Keep touch interaction
                        .offset(x: CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * sliderWidth - thumbSize / 2)
                        .gesture(
                            isDraggable ? DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let newValue = min(max(range.lowerBound, range.lowerBound + (gesture.location.x / sliderWidth) * (range.upperBound - range.lowerBound)), range.upperBound)
                                    let roundedNew = round(newValue)
                                    let roundedCurrent = round(value)

                                    if roundedNew != roundedCurrent {
                                        impactFeedback.impactOccurred()
                                    }
                                    value = newValue
                                    isDragging = true
                                    onEditingChanged(true) // Notify parent
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    onEditingChanged(false)
                                }
                            : nil // Disable dragging if `isDraggable == false`
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
    
    // Function to format time as hh:mm:ss or mm:ss
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

