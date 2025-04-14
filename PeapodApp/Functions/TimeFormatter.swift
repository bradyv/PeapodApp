//
//  Utility.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-19.
//

import Foundation

func formatDuration(seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : (minutes > 1 ? "\(minutes)m" : "\(seconds)s")
}

func getRelativeDateString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}
