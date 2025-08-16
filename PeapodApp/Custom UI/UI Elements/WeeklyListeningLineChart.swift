//
//  WeeklyListeningLineChart.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-08-15.
//

import SwiftUI
import Pow

struct WeeklyListeningLineChart: View {
    let weeklyData: [WeeklyListeningData]
    let favoriteDayName: String
    
    private let chartHeight: CGFloat = 92
    private let chartWidth: CGFloat = 200
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            
            ZStack {
                // The smooth line path
                WeeklyListeningPath(
                    weeklyData: weeklyData,
                    chartHeight: chartHeight,
                    chartWidth: availableWidth
                )
                .stroke(Color.heading, lineWidth: 2)
                
                // Peak dot and label
                if let peakDay = weeklyData.first(where: { $0.percentage == 1.0 }) {
                    let peakX = xPosition(for: peakDay.dayOfWeek - 1, width: availableWidth)
                    let peakY = yPosition(for: peakDay.percentage)
                    
                    VStack(spacing: 8) {
                        // Peak dot
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color.background, lineWidth: 2)
                            )
                    }
                    .position(x: peakX, y: peakY)
                }
            }
        }
        .frame(height: chartHeight) // Extra space for label and dot
    }
    
    private func xPosition(for dayIndex: Int, width: CGFloat) -> CGFloat {
        let padding: CGFloat = 20
        let availableWidth = width - (padding * 2)
        return padding + (availableWidth / 6) * CGFloat(dayIndex)
    }
    
    private func yPosition(for percentage: Double) -> CGFloat {
        let padding: CGFloat = 20
        let availableHeight = chartHeight - (padding * 2)
        return padding + availableHeight * (1.0 - percentage)
    }
}

struct WeeklyListeningPath: Shape {
    let weeklyData: [WeeklyListeningData]
    let chartHeight: CGFloat
    let chartWidth: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let padding: CGFloat = 20
        let availableWidth = rect.width - (padding * 2)
        let availableHeight = chartHeight - (padding * 2)
        
        // Create 9 points: 2 edge points + 7 day points
        var points: [CGPoint] = []
        
        // Start point (left edge)
        let startY = padding + availableHeight * (1.0 - (weeklyData.first?.percentage ?? 0.5))
        points.append(CGPoint(x: 0, y: startY))
        
        // Day points
        for (index, dayData) in weeklyData.enumerated() {
            let x = padding + (availableWidth / 6) * CGFloat(index)
            let y = padding + availableHeight * (1.0 - dayData.percentage)
            points.append(CGPoint(x: x, y: y))
        }
        
        // End point (right edge)
        let endY = padding + availableHeight * (1.0 - (weeklyData.last?.percentage ?? 0.5))
        points.append(CGPoint(x: rect.width, y: endY))
        
        // Create smooth curve through points
        guard points.count > 2 else { return path }
        
        path.move(to: points[0])
        
        for i in 1..<points.count {
            let currentPoint = points[i]
            
            if i == 1 {
                // First curve from edge to first day
                let controlPoint1 = CGPoint(x: points[0].x + 30, y: points[0].y)
                let controlPoint2 = CGPoint(x: currentPoint.x - 20, y: currentPoint.y)
                path.addCurve(to: currentPoint, control1: controlPoint1, control2: controlPoint2)
            } else if i == points.count - 1 {
                // Last curve from last day to edge
                let controlPoint1 = CGPoint(x: points[i-1].x + 20, y: points[i-1].y)
                let controlPoint2 = CGPoint(x: currentPoint.x - 30, y: currentPoint.y)
                path.addCurve(to: currentPoint, control1: controlPoint1, control2: controlPoint2)
            } else {
                // Smooth curves between days
                let previousPoint = points[i-1]
                let nextPoint = i < points.count - 1 ? points[i+1] : currentPoint
                
                let controlDistance: CGFloat = 15
                let controlPoint1 = CGPoint(
                    x: previousPoint.x + controlDistance,
                    y: previousPoint.y
                )
                let controlPoint2 = CGPoint(
                    x: currentPoint.x - controlDistance,
                    y: currentPoint.y
                )
                
                path.addCurve(to: currentPoint, control1: controlPoint1, control2: controlPoint2)
            }
        }
        
        return path
    }
}
