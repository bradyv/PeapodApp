import SwiftUI
import Charts

struct WeeklyListeningLineChart: View {
    let weeklyData: [WeeklyListeningData]
    let favoriteDayName: String
    
    private let chartHeight: CGFloat = 92
    
    private var paddedData: [WeeklyListeningData] {
        let dayAbbreviations = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        // Create complete week data (ensuring all 7 days are present)
        let completeWeekData = (1...7).map { dayOfWeek in
            weeklyData.first { $0.dayOfWeek == dayOfWeek } ??
            WeeklyListeningData(
                dayOfWeek: dayOfWeek,
                count: 0,
                percentage: 0.0,
                dayAbbreviation: dayAbbreviations[dayOfWeek]
            )
        }
        
        // Add padding points to create the bleed effect
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
            .interpolationMethod(.catmullRom) // Smooth curve interpolation
            
            // Peak dot - only show for actual days (1-7)
            if dayData.percentage == 1.0 && dayData.dayOfWeek >= 1 && dayData.dayOfWeek <= 7 {
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
        .chartBackground { _ in
            // Custom background if needed
            Color.clear
        }
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
            Text("Weekly Listening Pattern")
                .font(.headline)
                .padding()
            
            WeeklyListeningLineChart(
                weeklyData: WeeklyListeningLineChart.mockData,
                favoriteDayName: "Friday"
            )
            .padding()
            .background(Color.black)
            
            Text("You listen the most on Friday")
                .foregroundColor(.white)
                .padding()
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
