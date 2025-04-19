//
//  HTMLParser.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-26.
//

import Foundation
import SwiftSoup

func parseHtml(_ html: String, flat: Bool = false) -> String {
    do {
        let cleanedHtml = html
            .replacingOccurrences(of: "<br ?/?>", with: "</p><p>", options: .regularExpression)
            .replacingOccurrences(of: "\\n", with: "</p><p>", options: .regularExpression)

        let wrappedHtml = "<div>\(cleanedHtml)</div>"

        let document = try SwiftSoup.parse(wrappedHtml)
        guard let body = document.body() else {
            return "Error: Missing body tag"
        }

        var paragraphs: [String] = []
        var seen = Set<String>()

        for el in try body.select("p") {
            let text = try el.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if seen.insert(text).inserted {
                paragraphs.append(text)
            }
        }

        return paragraphs.joined(separator: flat ? " " : "\n\n")

    } catch {
        return "Error parsing HTML"
    }
}

func parseHtmlToAttributed(_ html: String) -> AttributedString {
    do {
        let cleanedHtml = html
            .replacingOccurrences(of: "<br ?/?>", with: "</p><p>", options: .regularExpression)
            .replacingOccurrences(of: "\\n", with: "</p><p>", options: .regularExpression)

        let wrappedHtml = "<div>\(cleanedHtml)</div>"

        guard let data = wrappedHtml.data(using: .utf8) else {
            return AttributedString("Error loading description")
        }

        let attributed = try NSMutableAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )

        // Keep existing links and clear everything else
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            var newAttributes: [NSAttributedString.Key: Any] = [:]
            if let link = attributes[.link] {
                newAttributes[.link] = link
            }
            attributed.setAttributes(newAttributes, range: range)
        }

        // 🔍 Detect plain URLs not already linked
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let plainString = attributed.string
        let matches = detector.matches(in: plainString, options: [], range: NSRange(location: 0, length: plainString.utf16.count))

        for match in matches {
            guard let url = match.url else { continue }

            let range = match.range
            // Avoid overriding existing links
            if attributed.attribute(.link, at: range.location, effectiveRange: nil) == nil {
                attributed.addAttribute(.link, value: url, range: range)
            }
        }

        return try AttributedString(attributed, including: \.uiKit)

    } catch {
        return AttributedString("Error loading description")
    }
}
