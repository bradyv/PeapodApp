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

        var blocks: [AttributedString] = []
        
        for node in body.getChildNodes() {
            let (parsed, isBlock) = parseNode(node, font: font, color: color, linkColor: linkColor, isTopLevel: true)
            
            if !parsed.characters.isEmpty {
                blocks.append(parsed)
            }
        }
        
        // Join blocks with exactly one blank line between them
        for (index, block) in blocks.enumerated() {
            result.append(block)
            if index < blocks.count - 1 {
                result.append(AttributedString("\n\n"))
            }
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
    
    // Flatten nested paragraphs: <p><p>...</p></p> → <p>...</p>
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
    
    // Convert multiple <br> tags into paragraph breaks
    cleaned = cleaned.replacingOccurrences(
        of: "(<br>\\s*){2,}",
        with: "</p><p>",
        options: [.regularExpression, .caseInsensitive]
    )

    return cleaned
}

func linkifyPlainUrls(in input: AttributedString, linkColor: Color = .accentColor) -> AttributedString {
    var result = input
    let text = String(input.characters)
    let nsString = text as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)

    // Pattern for URLs with protocol
    let urlWithProtocolPattern = #"https?://[^\s]+"#
    // Pattern for domain-like strings (e.g., example.com/path)
    let domainPattern = #"\b[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:/[^\s]*)?"#
    // Pattern for email addresses
    let emailPattern = #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#
    
    // Combine all patterns
    let combinedPattern = "(\(urlWithProtocolPattern))|(\(domainPattern))|(\(emailPattern))"
    
    guard let regex = try? NSRegularExpression(pattern: combinedPattern, options: []) else {
        return result
    }

    let matches = regex.matches(in: text, options: [], range: fullRange)

    for match in matches.reversed() {
        guard let range = Range(match.range, in: result) else { continue }
        let matchedString = nsString.substring(with: match.range)
        
        // Skip if this text already has a link
        if result[range].link != nil {
            continue
        }
        
        let url: URL?
        if matchedString.contains("@") {
            // Email address
            url = URL(string: "mailto:\(matchedString)")
        } else if matchedString.hasPrefix("http://") || matchedString.hasPrefix("https://") {
            // Already has protocol
            url = URL(string: matchedString)
        } else {
            // Domain without protocol - add https://
            url = URL(string: "https://\(matchedString)")
        }

        if let url = url {
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
        linked.foregroundColor = linkColor
        result.replaceSubrange(swiftRange, with: linked)
    }

    return result
}

private func parseNode(_ node: Node, font: Font, color: Color, linkColor: Color = .accentColor, isTopLevel: Bool = false) -> (AttributedString, Bool) {
    var output = AttributedString()
    var isBlockElement = false

    if let textNode = node as? TextNode {
        let text = textNode.text()
        
        // For top-level text nodes, trim them completely
        // For inline text nodes, normalize whitespace but preserve single spaces
        let processedText = isTopLevel
            ? text.trimmingCharacters(in: .whitespacesAndNewlines)
            : text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        if !processedText.isEmpty {
            var attrText = AttributedString(processedText)
            attrText.font = font
            attrText.foregroundColor = color
            output.append(attrText)
        }
    }

    else if let element = node as? Element {
        let tagName = element.tagName().lowercased()
        
        // Determine if this is a block-level element
        let blockTags: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote"]
        isBlockElement = blockTags.contains(tagName)
        
        switch tagName {
        case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote":
            // Process children as inline content
            for child in element.getChildNodes() {
                let (childOutput, _) = parseNode(child, font: font, color: color, linkColor: linkColor, isTopLevel: false)
                output.append(childOutput)
            }
            // Trim the final paragraph content
            output = AttributedString(String(output.characters).trimmingCharacters(in: .whitespacesAndNewlines))
            var formatted = output
            formatted.font = font
            formatted.foregroundColor = color
            output = formatted

        case "br":
            // Convert BR to a line break only if we're inside a paragraph
            if !isTopLevel {
                output.append(AttributedString("\n"))
            }

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
                var (childOutput, _) = parseNode(child, font: font, color: color, linkColor: linkColor, isTopLevel: false)
                childOutput.inlinePresentationIntent = .stronglyEmphasized
                output.append(childOutput)
            }

        case "em", "i":
            for child in element.getChildNodes() {
                var (childOutput, _) = parseNode(child, font: font, color: color, linkColor: linkColor, isTopLevel: false)
                childOutput.inlinePresentationIntent = .emphasized
                output.append(childOutput)
            }

        case "ul", "ol":
            // Handle lists as block elements
            var listOutput = AttributedString()
            for (index, child) in element.getChildNodes().enumerated() {
                let (childOutput, _) = parseNode(child, font: font, color: color, linkColor: linkColor, isTopLevel: false)
                if !childOutput.characters.isEmpty {
                    if index > 0 {
                        listOutput.append(AttributedString("\n"))
                    }
                    let bullet = tagName == "ul" ? "• " : "\(index + 1). "
                    var bulletAttr = AttributedString(bullet)
                    bulletAttr.font = font
                    bulletAttr.foregroundColor = color
                    listOutput.append(bulletAttr)
                    listOutput.append(childOutput)
                }
            }
            output = listOutput

        case "li":
            // Just parse the content of list items
            for child in element.getChildNodes() {
                let (childOutput, _) = parseNode(child, font: font, color: color, linkColor: linkColor, isTopLevel: false)
                output.append(childOutput)
            }

        default:
            // For unknown tags, just parse children
            for child in element.getChildNodes() {
                let (childOutput, _) = parseNode(child, font: font, color: color, linkColor: linkColor, isTopLevel: isTopLevel)
                output.append(childOutput)
            }
        }
    }

    return (output, isBlockElement)
}
