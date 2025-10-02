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

func parseHtmlToAttributedString(_ html: String, linkColor: Color = .accentColor) -> AttributedString {
    var result = AttributedString()

    let font = Font.system(size: 17, weight: .regular, design: .default).width(.condensed)
    let color = Color.text

    do {
        let cleanHtml = sanitizeHtml(html)
        let doc = try SwiftSoup.parse(cleanHtml)
        guard let body = try doc.body() else { return AttributedString("No content") }

        for node in body.getChildNodes() {
            let parsed = parseNode(node, font: font, color: color, linkColor: linkColor)
            
            // Add spacing before this node if result already has content
            // and the parsed node is not empty
            if !result.characters.isEmpty && !parsed.characters.isEmpty {
                result.append(AttributedString("\n\n"))
            }
            
            result.append(parsed)
        }

        let result = linkifyPlainUrls(in: result, linkColor: linkColor)
        return linkifyTimestamps(in: result, linkColor: linkColor)

    } catch {
        return AttributedString("Error parsing description")
    }
}

func sanitizeHtml(_ html: String) -> String {
    var cleaned = html

    // Normalize all <br> to consistent tag
    cleaned = cleaned.replacingOccurrences(of: "<br ?/?>", with: "<br>", options: .regularExpression)

    // Remove empty <p><br></p>
    cleaned = cleaned.replacingOccurrences(of: "<p>\\s*<br>\\s*</p>", with: "", options: [.regularExpression, .caseInsensitive])

    // Remove entirely empty paragraphs
    cleaned = cleaned.replacingOccurrences(of: "<p>\\s*</p>", with: "", options: [.regularExpression, .caseInsensitive])
    
    // ✅ Flatten nested paragraphs: <p><p>...</p></p> → <p>...</p>
    // This works by repeatedly replacing outer <p><p> and inner </p></p> until they’re flattened
    while cleaned.contains("<p><p>") || cleaned.contains("</p></p>") {
        cleaned = cleaned
            .replacingOccurrences(of: "<p><p>", with: "<p>", options: .caseInsensitive)
            .replacingOccurrences(of: "</p></p>", with: "</p>", options: .caseInsensitive)
    }

    // Trim leading whitespace inside paragraphs (spaces, tabs, &nbsp;)
    cleaned = cleaned.replacingOccurrences(
        of: "<p>\\s+",
        with: "<p>",
        options: [.regularExpression, .caseInsensitive]
    )

    return cleaned
}

func linkifyPlainUrls(in input: AttributedString, linkColor: Color = .accentColor) -> AttributedString {
    var result = input
    let text = String(input.characters)
    let nsString = text as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)

    // Improved URL regex pattern
    let urlPattern = #"https?://[^\s]+"#
    guard let regex = try? NSRegularExpression(pattern: urlPattern, options: []) else {
        return result
    }

    let matches = regex.matches(in: text, options: [], range: fullRange)

    for match in matches.reversed() {
        guard let range = Range(match.range, in: result) else { continue }
        let urlString = nsString.substring(with: match.range)

        if let url = URL(string: urlString) {
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

    // Match timestamps like 1:23:45, 12:34, or 5:06
    let regex = try! NSRegularExpression(pattern: #"\b(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\b"#)

    let matches = regex.matches(in: text, options: [], range: fullRange)

    for match in matches.reversed() {
        let range = match.range
        guard let swiftRange = Range(range, in: result) else { continue }

        // Extract time components
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
        linked.foregroundColor = linkColor // Optional: color it like a link
        result.replaceSubrange(swiftRange, with: linked)
    }

    return result
}


private func parseNode(_ node: Node, font: Font, color: Color, linkColor: Color = .accentColor) -> AttributedString {
    var output = AttributedString()

    if let textNode = node as? TextNode {
        let text = textNode.text()
        // Only skip completely empty/whitespace-only nodes
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var attrText = AttributedString(text)
            attrText.font = font
            attrText.foregroundColor = color
            output.append(attrText)
        }
    }

    else if let element = node as? Element {
        switch element.tagName().lowercased() {
        case "p":
            for child in element.getChildNodes() {
                output.append(parseNode(child, font: font, color: color, linkColor: linkColor))
            }

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

        case "strong", "b":
            for child in element.getChildNodes() {
                var childOutput = parseNode(child, font: font, color: color, linkColor: linkColor)
                childOutput.inlinePresentationIntent = .stronglyEmphasized
                output.append(childOutput)
            }

        case "em", "i":
            for child in element.getChildNodes() {
                var childOutput = parseNode(child, font: font, color: color, linkColor: linkColor)
                childOutput.inlinePresentationIntent = .emphasized
                output.append(childOutput)
            }

        default:
            for child in element.getChildNodes() {
                output.append(parseNode(child, font: font, color: color, linkColor: linkColor))
            }
        }
    }

    return output
}
