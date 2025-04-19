//
//  HTMLParser.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-26.
//

import SwiftUI
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

func parseHtmlToAttributedString(_ html: String) -> AttributedString {
    var result = AttributedString()

    let font = Font.system(size: 17, weight: .regular, design: .default).width(.condensed)
    let color = Color.text

    do {
        let doc = try SwiftSoup.parse(html)
        guard let body = try doc.body() else { return AttributedString("No content") }

        for node in body.getChildNodes() {
            result.append(parseNode(node, font: font, color: color))
        }

        return linkifyPlainUrls(in: result)

    } catch {
        return AttributedString("Error parsing description")
    }
}

func linkifyPlainUrls(in input: AttributedString) -> AttributedString {
    var result = input
    let nsString = NSString(string: String(input.characters))
    let fullRange = NSRange(location: 0, length: nsString.length)

    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return result
    }

    let matches = detector.matches(in: String(input.characters), options: [], range: fullRange)

    for match in matches {
        guard let range = Range(match.range, in: result) else { continue }
        if let url = match.url {
            result[range].link = url
            result[range].foregroundColor = .blue // Optional: make it visibly styled
        }
    }

    return result
}

private func parseNode(_ node: Node, font: Font, color: Color) -> AttributedString {
    var output = AttributedString()

    if let textNode = node as? TextNode {
        var text = AttributedString(textNode.text())
        text.font = font
        text.foregroundColor = color
        output.append(text)
    }

    else if let element = node as? Element {
        switch element.tagName().lowercased() {
        case "p":
            for child in element.getChildNodes() {
                output.append(parseNode(child, font: font, color: color))
            }
            output.append(AttributedString("\n\n"))

        case "br":
            output.append(AttributedString("\n"))

        case "a":
            let label = try? element.text()
            let href = try? element.attr("href")
            if let label, let href, let url = URL(string: href) {
                var link = AttributedString(label)
                link.font = font
                link.foregroundColor = .blue
                link.link = url
                output.append(link)
            }

        default:
            for child in element.getChildNodes() {
                output.append(parseNode(child, font: font, color: color))
            }
        }
    }

    return output
}
