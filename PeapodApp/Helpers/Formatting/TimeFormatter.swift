//
//  Utility.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-19.
//

import SwiftUI

func formatDuration(seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : (minutes > 1 ? "\(minutes)m" : "\(seconds)s")
}

func getRelativeDateString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    return formatter.localizedString(for: date, relativeTo: Date()).capitalized
}

struct RoundedRelativeDateView: View {
    let date: Date
    
    // 1. A state variable to hold the "current" time, updated by the timer
    @State private var currentDate: Date = .now
    
    // 2. A timer that publishes every 60 seconds
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // 3. A DateComponentsFormatter configured to show only ONE unit
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        
        // Use all common units
        formatter.allowedUnits = [.year, .month, .day, .hour, .minute]
        
        // This is the magic property:
        formatter.maximumUnitCount = 1
        
        // Get "20 hours" instead of "20 hrs"
        formatter.unitsStyle = .full
        return formatter
    }()
    
    var body: some View {
        // 4. The Text view, which gets its string from our logic
        Text(formattedDateString)
            .onReceive(timer) { newTime in
                // 5. When the timer fires, update the state, forcing a re-render
                self.currentDate = newTime
            }
    }
    
    // 6. This computed property creates the final string
    private var formattedDateString: String {
        // Get the base string, e.g., "20 hours" or "5 minutes"
        let relativeString = Self.formatter.string(from: date, to: currentDate) ?? ""
        
        // Check if the date is in the future or past
        if date > currentDate {
            return "in \(relativeString)"
        } else {
            // Handle the "just now" case
            if relativeString.isEmpty || relativeString == "0 minutes" {
                return "Just now"
            }
            return "\(relativeString) ago"
        }
    }
}
