//
//  ColorDarkener.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI

extension UIColor {
    func darkened(by percentage: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }

        return UIColor(hue: hue,
                       saturation: saturation,
                       brightness: max(brightness - percentage, 0),
                       alpha: alpha)
    }
}

extension Color {
    func darkened(by percentage: CGFloat) -> Color {
        let uiColor = UIColor(self)
        return Color(uiColor.darkened(by: percentage))
    }
}
