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
        let document = try SwiftSoup.parse(html)
        guard let body = document.body() else {
            return html.trimmingCharacters(in: .whitespacesAndNewlines)
        }

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

func parseHtmlToAttributedString(_ html: String, linkColor: Color = .accentColor) -> AttributedString {
    var result = AttributedString()
    let font = Font.system(size: 17, weight: .regular, design: .default).width(.condensed)
    let color = Color.text

    do {
        let doc = try SwiftSoup.parse(normalizeHtml(html))
        guard let body = try doc.body() else { return AttributedString("No content") }

        for node in body.getChildNodes() {
            result.append(parseNode(node, font: font, color: color, linkColor: linkColor))
        }

        let result = linkifyPlainUrls(in: result, linkColor: linkColor)
        return linkifyTimestamps(in: result, linkColor: linkColor)

    } catch {
        return AttributedString("Error parsing description")
    }
}

func normalizeHtml(_ html: String) -> String {
    var cleaned = html

    // Normalize line breaks
    cleaned = cleaned.replacingOccurrences(of: "<br ?/?>", with: "\n", options: .regularExpression)

    // Remove empty or whitespace-only paragraphs
    cleaned = cleaned.replacingOccurrences(of: "<p>\\s*</p>", with: "", options: [.regularExpression, .caseInsensitive])

    // Convert <div> to <p>
    if let regex = try? NSRegularExpression(pattern: "<div>(.*?)</div>", options: [.dotMatchesLineSeparators, .caseInsensitive]) {
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "<p>$1</p>")
    }

    // Extract all text inside <p>...</p> and manually segment if too long or containing timestamps
    let pattern = "<p>(.*?)</p>"
    if let paragraphRegex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
        let nsCleaned = cleaned as NSString
        let matches = paragraphRegex.matches(in: cleaned, options: [], range: NSRange(location: 0, length: nsCleaned.length))

        var reconstructed = ""

        for match in matches {
            let content = nsCleaned.substring(with: match.range(at: 1))

            // Split at newlines or timestamp markers
            let segments = content
                .components(separatedBy: "\n")
                .flatMap { $0.components(separatedBy: #"(?=\b\d{1,2}:\d{2}(:\d{2})?)"#) } // split on timestamps
                .flatMap { $0.components(separatedBy: #"(?=https?://)"#) } // split on links
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for segment in segments {
                reconstructed.append("<p>\(segment)</p>")
            }
        }

        cleaned = reconstructed
    }

    return cleaned
}

func linkifyPlainUrls(in input: AttributedString, linkColor: Color = .accentColor) -> AttributedString {
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
            result[range].foregroundColor = linkColor
        }
    }

    return result
}

func linkifyTimestamps(in input: AttributedString, linkColor: Color = .accentColor) -> AttributedString {
    var result = input
    let text = String(input.characters)
    let nsString = NSString(string: text)
    let fullRange = NSRange(location: 0, length: nsString.length)

    let regex = try! NSRegularExpression(pattern: #"\b(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\b"#)

    let matches = regex.matches(in: text, options: [], range: fullRange)

    for match in matches.reversed() {
        let range = match.range
        guard let swiftRange = Range(range, in: result) else { continue }

        let fullMatch = nsString.substring(with: range)
        let components = fullMatch.split(separator: ":").compactMap { Int($0) }
        guard !components.isEmpty else { continue }

        let seconds: Int
        switch components.count {
        case 3:
            seconds = components[0] * 3600 + components[1] * 60 + components[2]
        case 2:
            seconds = components[0] * 60 + components[1]
        default:
            continue
        }

        let url = URL(string: "peapod://seek?t=\(seconds)")!
        var linked = result[swiftRange]
        linked.link = url
        linked.foregroundColor = linkColor
        result.replaceSubrange(swiftRange, with: linked)
    }

    return result
}

private func parseNode(_ node: Node, font: Font, color: Color, linkColor: Color = .accentColor) -> AttributedString {
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
                output.append(parseNode(child, font: font, color: color, linkColor: linkColor))
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
                link.foregroundColor = linkColor
                link.link = url
                output.append(link)
            }

        default:
            for child in element.getChildNodes() {
                output.append(parseNode(child, font: font, color: color, linkColor: linkColor))
            }
        }
    }

    return output
}
