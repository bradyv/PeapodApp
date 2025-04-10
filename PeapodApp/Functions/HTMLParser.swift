//
//  HTMLParser.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-26.
//

import Foundation
import SwiftSoup

func parseHtml(_ html: String) -> String {
    do {
        let document = try SwiftSoup.parse(html)

        // If the body has no elements, treat it as plain text
        if let body = document.body(), body.children().isEmpty {
            let fallbackText = try body.text()
            return fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result = ""

        for child in document.body()?.getChildNodes() ?? [] {
            if let element = child as? Element {
                let tag = try element.tagName()

                if tag == "p" || tag == "div" {
                    let innerText = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(innerText.isEmpty ? "\n" : innerText + "\n\n")
                } else if tag == "br" {
                    result.append("\n")
                } else {
                    let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        result.append(text + "\n")
                    }
                }
            }
        }

        return result
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

    } catch {
        return "Error parsing HTML"
    }
}

func parseHtmlFlat(_ html: String) -> String {
    do {
        let document = try SwiftSoup.parse(html)

        // If the body has no elements, treat it as plain text
        if let body = document.body(), body.children().isEmpty {
            let fallbackText = try body.text()
            return fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result = ""

        for child in document.body()?.getChildNodes() ?? [] {
            if let element = child as? Element {
                let tag = try element.tagName()

                if tag == "p" || tag == "div" {
                    let innerText = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(innerText.isEmpty ? "" : innerText + "")
                } else if tag == "br" {
                    result.append("")
                } else {
                    let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        result.append(text + "")
                    }
                }
            }
        }

        return result
            .replacingOccurrences(of: "\n{3,}", with: "", options: .regularExpression)
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
