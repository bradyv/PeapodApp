//
//  ColorExtractor.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-24.
//

import UIKit
import SwiftUI
import ColorThiefSwift

struct ColorVariants: Codable, Equatable {
    let accent: String   // hex for decoration
    let highContrast: String // hex for background
}

// MARK: - ColorExtractor
enum ColorExtractor {
    static func extractColorVariants(from image: UIImage) -> ColorVariants? {
        guard let resized = image.resized(to: CGSize(width: 100, height: 100)),
              let palette = ColorThief.getPalette(from: resized, colorCount: 5, quality: 1) else {
            return nil
        }

        let filtered = palette.filter { color in
            let r = CGFloat(color.r) / 255.0
            let g = CGFloat(color.g) / 255.0
            let b = CGFloat(color.b) / 255.0

            let brightness = (r * 299 + g * 587 + b * 114) / 1000
            let saturation = max(r, g, b) - min(r, g, b)

            return brightness > 0.2 && brightness < 0.9 && saturation > 0.1
        }

        guard let best = filtered.first ?? palette.first else { return nil }

        let accentColor = UIColor(
            red: CGFloat(best.r) / 255,
            green: CGFloat(best.g) / 255,
            blue: CGFloat(best.b) / 255,
            alpha: 1.0
        )

        let highContrast = accentColor.highContrastVariant()

        return ColorVariants(
            accent: accentColor.toHexString(),
            highContrast: highContrast.toHexString()
        )
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex = hex, let uiColor = UIColor(hex) else { return nil }
        self = Color(uiColor)
    }
}

extension UIColor {
    func toHexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)))
    }

    convenience init?(_ hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexSanitized.hasPrefix("#") { hexSanitized.removeFirst() }

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    func highContrastVariant() -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        if getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let newBrightness = brightness < 0.5 ? min(brightness + 0.4, 1.0) : max(brightness - 0.4, 0)
            let newSaturation = max(min(saturation * 1.2, 1.0), 0.4)
            return UIColor(hue: hue, saturation: newSaturation, brightness: newBrightness, alpha: alpha)
        }
        return self
    }
}
