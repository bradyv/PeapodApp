//
//  ColorExtractor.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-24.
//

import UIKit
import SwiftUI
import ColorThiefSwift
import Kingfisher
@preconcurrency import CoreData

struct ColorVariants: Codable, Equatable {
    let accent: String   // hex for decoration
    let highContrast: String // hex for background
}

// MARK: - ColorExtractor
enum ColorExtractor {
    static func extractAccentAndContrast(from image: UIImage) -> (accent: String, highContrast: String)? {
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

        let base = UIColor(
            red: CGFloat(best.r) / 255,
            green: CGFloat(best.g) / 255,
            blue: CGFloat(best.b) / 255,
            alpha: 1.0
        )

        let contrastWithWhite = base.contrastRatio(with: UIColor.white)
        if contrastWithWhite >= 3.5 {
            return (base.toHexString(), base.toHexString())
        }

        let darkened = base.highContrastVariant()
        let final = darkened.contrastRatio(with: UIColor.white) >= 3.5 ? darkened : base

        return (base.toHexString(), final.toHexString())
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
    
    func contrastRatio(with other: UIColor) -> CGFloat {
        func luminance(_ color: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)

            func adjust(_ c: CGFloat) -> CGFloat {
                return (c < 0.03928) ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4)
            }

            let lR = adjust(r)
            let lG = adjust(g)
            let lB = adjust(b)

            return 0.2126 * lR + 0.7152 * lG + 0.0722 * lB
        }

        let lum1 = luminance(self)
        let lum2 = luminance(other)

        let lighter = max(lum1, lum2)
        let darker = min(lum1, lum2)

        return (lighter + 0.05) / (darker + 0.05)
    }
}

// MARK: - ColorTintManager
enum ColorTintManager {
    static func applyTintIfNeeded(to podcast: Podcast, in context: NSManagedObjectContext) {
        guard podcast.podcastTint == nil,
              let imageUrlString = podcast.image,
              !imageUrlString.isEmpty,
              let imageUrl = URL(string: imageUrlString) else { return }

        let objectID = podcast.objectID

        KingfisherManager.shared.retrieveImage(with: imageUrl) { result in
            switch result {
            case .success(let value):
                if let (accent, highContrast) = ColorExtractor.extractAccentAndContrast(from: value.image) {
                    context.perform {
                        if let object = try? context.existingObject(with: objectID) as? Podcast {
                            object.podcastTint = accent
                            object.podcastTintDarkened = highContrast
                            try? context.save()
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }

    static func applyTintIfNeeded(to episode: Episode, in context: NSManagedObjectContext) {
        guard episode.episodeTint == nil,
              let feedImage = episode.episodeImage,
              !feedImage.isEmpty,
              let imageUrl = URL(string: feedImage) else { return }

        let objectID = episode.objectID

        KingfisherManager.shared.retrieveImage(with: imageUrl) { result in
            switch result {
            case .success(let value):
                if let (accent, highContrast) = ColorExtractor.extractAccentAndContrast(from: value.image) {
                    context.perform {
                        if let object = try? context.existingObject(with: objectID) as? Episode {
                            object.episodeTint = accent
                            object.episodeTintDarkened = highContrast
                            try? context.save()
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }
}

extension Color {
    static func tint(for episode: Episode, opacity: CGFloat = 1, darkened: Bool = false) -> Color {
        return (Color(hex: darkened ? episode.episodeTintDarkened : episode.episodeTint)?.opacity(opacity)) ??
               tint(for: episode.podcast, opacity: opacity, darkened: darkened)
    }

    static func tint(for podcast: Podcast?, opacity: CGFloat = 1, darkened: Bool = false) -> Color {
        return (Color(hex: darkened ? podcast?.podcastTintDarkened : podcast?.podcastTint)?.opacity(opacity)) ??
               Color.black.opacity(opacity)
    }
}

func resetAllTints(in context: NSManagedObjectContext) {
    context.perform {
        let podcastRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()

        do {
            let podcasts = try context.fetch(podcastRequest)
            for podcast in podcasts {
                podcast.podcastTint = nil
                podcast.podcastTintDarkened = nil
            }

            let episodes = try context.fetch(episodeRequest)
            for episode in episodes {
                episode.episodeTint = nil
                episode.episodeTintDarkened = nil
            }

            try context.save()
            LogManager.shared.info("✅ Successfully reset all tint values.")

        } catch {
            LogManager.shared.error("❌ Failed to reset tints: \(error.localizedDescription)")
        }
    }
}
