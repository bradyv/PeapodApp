//
//  Colors.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-29.
//

import SwiftUI

var cardBackgroundGradient: LinearGradient {
    LinearGradient(
        stops: [
            Gradient.Stop(color: .white.opacity(0.3), location: 0.00),
            Gradient.Stop(color: .white.opacity(0), location: 1.00),
        ],
        startPoint: UnitPoint(x: 0, y: 0),
        endPoint: UnitPoint(x: 0.5, y: 1)
    )
}
