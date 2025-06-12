//
//  Episode+Extension.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-06-02.
//

import Foundation
import CoreData

extension Episode {
    func getPlayedDatesArray() -> [Date] {
        return playedDates as? [Date] ?? []
    }
    
    func setPlayedDatesArray(_ dates: [Date]) {
        playedDates = dates as NSObject
    }
    
    func addPlayedDate(_ date: Date) {
        let currentDates = getPlayedDatesArray()
        setPlayedDatesArray(currentDates + [date])
        playCount = Int64(currentDates.count + 1)
    }
}
