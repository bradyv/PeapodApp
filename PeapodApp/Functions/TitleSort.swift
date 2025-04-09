//
//  TitleSort.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-09.
//

import Foundation

extension String {
    func trimmedTitle() -> String {
        if self.lowercased().hasPrefix("the ") {
            return String(self.dropFirst(4)) // Drops "The " (4 characters)
        }
        return self
    }
}
