//
//  WeeklyListeningLineChart.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-08-12.
//

import SwiftUI
import Charts

struct WeeklyListeningLineChart: View {
    let weeklyData: [WeeklyListeningData]
    let favoriteDayName: String
    let chartHeight: CGFloat
    let showPeakDot: Bool
    
    // Default initializer with optional height and showPeakDot parameters
    init(weeklyData: [WeeklyListeningData], favoriteDayName: String, chartHeight: CGFloat = 92, showPeakDot: Bool = true) {
        self.weeklyData = weeklyData
        self.favoriteDayName = favoriteDayName
        self.chartHeight = chartHeight
        self.showPeakDot = showPeakDot
    }
    
    // Find the single peak day
    private var peakDay: Int? {
        weeklyData.max(by: { $0.percentage < $1.percentage })?.dayOfWeek
    }
    
    private var paddedData: [WeeklyListeningData] {
        let dayAbbreviations = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        let completeWeekData = (1...7).map { dayOfWeek in
            weeklyData.first { $0.dayOfWeek == dayOfWeek } ??
            WeeklyListeningData(
                dayOfWeek: dayOfWeek,
                count: 0,
                percentage: 0.0,
                dayAbbreviation: dayAbbreviations[dayOfWeek]
            )
        }
        
        let firstPercentage = completeWeekData.first?.percentage ?? 0
        let lastPercentage = completeWeekData.last?.percentage ?? 0
        
        let paddingStart = WeeklyListeningData(
            dayOfWeek: 0,
            count: 0,
            percentage: firstPercentage,
            dayAbbreviation: ""
        )
        
        let paddingEnd = WeeklyListeningData(
            dayOfWeek: 8,
            count: 0,
            percentage: lastPercentage,
            dayAbbreviation: ""
        )
        
        return [paddingStart] + completeWeekData + [paddingEnd]
    }
    
    var body: some View {
        Chart(paddedData, id: \.dayOfWeek) { dayData in
            LineMark(
                x: .value("Day", dayData.dayOfWeek),
                y: .value("Percentage", dayData.percentage)
            )
            .foregroundStyle(Color.heading)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
            
            // Show dot ONLY for the single peak day
            if showPeakDot,
               let peakDay = peakDay,
               dayData.dayOfWeek == peakDay {
                PointMark(
                    x: .value("Day", dayData.dayOfWeek),
                    y: .value("Percentage", dayData.percentage)
                )
                .foregroundStyle(Color.accentColor)
                .symbol {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.background, lineWidth: 3))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartXScale(domain: 0...8)
        .frame(height: chartHeight)
    }
}

extension WeeklyListeningLineChart {
    static var mockData: [WeeklyListeningData] {
        [
            WeeklyListeningData(dayOfWeek: 1, count: 2, percentage: 0.3, dayAbbreviation: "Sun"),
            WeeklyListeningData(dayOfWeek: 2, count: 5, percentage: 0.7, dayAbbreviation: "Mon"),
            WeeklyListeningData(dayOfWeek: 3, count: 3, percentage: 0.4, dayAbbreviation: "Tue"),
            WeeklyListeningData(dayOfWeek: 4, count: 1, percentage: 0.1, dayAbbreviation: "Wed"),
            WeeklyListeningData(dayOfWeek: 5, count: 4, percentage: 0.6, dayAbbreviation: "Thu"),
            WeeklyListeningData(dayOfWeek: 6, count: 7, percentage: 1.0, dayAbbreviation: "Fri"), // Peak day
            WeeklyListeningData(dayOfWeek: 7, count: 6, percentage: 0.8, dayAbbreviation: "Sat")
        ]
    }
}

struct WeeklyListeningLineChart_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Weekly Listening Pattern - Default Height")
                .font(.headline)
                .padding()
            
            // Using default height (92) and showing dot
            WeeklyListeningLineChart(
                weeklyData: WeeklyListeningLineChart.mockData,
                favoriteDayName: "Friday"
            )
            .padding()
            .background(Color.black)
            
            Text("You listen the most on Friday")
                .foregroundColor(.white)
                .padding()
            
            Divider()
                .background(Color.white)
                .padding()
            
            Text("Weekly Listening Pattern - Custom Height")
                .font(.headline)
                .padding()
            
            // Using custom height (150)
            WeeklyListeningLineChart(
                weeklyData: WeeklyListeningLineChart.mockData,
                favoriteDayName: "Friday",
                chartHeight: 150
            )
            .padding()
            .background(Color.black)
            
            Text("Same chart with custom height")
                .foregroundColor(.white)
                .padding()
            
            Divider()
                .background(Color.white)
                .padding()
            
            Text("Weekly Listening Pattern - No Peak Dot")
                .font(.headline)
                .padding()
            
            // Hiding the peak dot
            WeeklyListeningLineChart(
                weeklyData: WeeklyListeningLineChart.mockData,
                favoriteDayName: "Friday",
                showPeakDot: false
            )
            .padding()
            .background(Color.black)
            
            Text("Chart without peak indicator")
                .foregroundColor(.white)
                .padding()
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
