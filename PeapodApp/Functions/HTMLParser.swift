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
        let document = try SwiftSoup.parse(html)

        guard let body = document.body() else {
            return html.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If the body has no children, treat as plain text
        if body.children().isEmpty {
            let fallbackText = try body.text()
            return fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result = ""

        for child in body.getChildNodes() {
            if let element = child as? Element {
                let tag = try element.tagName()
                let innerText = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)

                if innerText.isEmpty { continue }

                switch tag {
                case "p", "div":
                    result.append(flat ? innerText : innerText + "\n\n")
                case "br":
                    if !flat { result.append("\n") }
                default:
                    result.append(flat ? innerText : innerText + "\n")
                }
            } else if let textNode = child as? TextNode {
                let text = textNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    result.append(flat ? text : text + "\n\n")
                }
            }
        }

        return result
            .replacingOccurrences(of: flat ? "\n" : "\n{3,}", with: flat ? "" : "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

    } catch {
        return "Error parsing HTML"
    }
}


func parseHtmlToAttributed(_ html: String) -> AttributedString {
    guard let data = html.data(using: .utf8) else { return AttributedString("Error loading description") }

    do {
        let attributed = try NSMutableAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        return try AttributedString(attributed, including: \.uiKit)
    } catch {
        return AttributedString("Error loading description")
    }
}
