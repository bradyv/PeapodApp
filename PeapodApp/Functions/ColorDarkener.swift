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

extension Color {
    static func tint(for episode: Episode, opacity: CGFloat = 1) -> Color {
        return (Color(hex: episode.episodeTint)?.opacity(opacity)) ??
               tint(for: episode.podcast, opacity: opacity)
    }
    
    static func tint(for podcast: Podcast?, opacity: CGFloat = 1) -> Color {
        return (Color(hex: podcast?.podcastTint)?.opacity(opacity)) ??
               Color.black.opacity(opacity)
    }
}
