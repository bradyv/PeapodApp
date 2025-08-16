import SwiftUI
import Charts

struct WeeklyListeningLineChart: View {
    let weeklyData: [WeeklyListeningData]
    let favoriteDayName: String
    
    private let chartHeight: CGFloat = 92
    
    var body: some View {
        Chart(weeklyData, id: \.dayOfWeek) { dayData in
            LineMark(
                x: .value("Day", dayData.dayOfWeek),
                y: .value("Percentage", dayData.percentage)
            )
            .foregroundStyle(Color.heading)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom) // Smooth curve interpolation
            
            // Peak dot
            if dayData.percentage == 1.0 {
                PointMark(
                    x: .value("Day", dayData.dayOfWeek),
                    y: .value("Percentage", dayData.percentage)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(144) // 12x12 circle
                .symbol(.circle)
            }
        }
        .chartXAxis(.hidden) // Hide X axis if you don't want day labels
        .chartYAxis(.hidden) // Hide Y axis
        .chartYScale(domain: 0...1) // Set Y scale from 0 to 1
        .chartXScale(domain: 1...7) // Days 1-7
        .frame(height: chartHeight)
        .chartBackground { _ in
            // Custom background if needed
            Color.clear
        }
    }
}

// Alternative version with more customization
struct WeeklyListeningLineChartAdvanced: View {
    let weeklyData: [WeeklyListeningData]
    let favoriteDayName: String
    
    private let chartHeight: CGFloat = 92
    
    var body: some View {
        Chart(weeklyData, id: \.dayOfWeek) { dayData in
            LineMark(
                x: .value("Day", dayData.dayOfWeek),
                y: .value("Percentage", dayData.percentage)
            )
            .foregroundStyle(Color.heading)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
            
            // Peak dot with custom styling
            if dayData.percentage == 1.0 {
                PointMark(
                    x: .value("Day", dayData.dayOfWeek),
                    y: .value("Percentage", dayData.percentage)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(144)
                .symbol {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.background, lineWidth: 2)
                        )
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartXScale(domain: 1...7)
        .frame(height: chartHeight)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.clear)
                .border(Color.clear)
        }
    }
}
