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
       let bodyHtml = try document.body()?.html() ?? ""

       let formattedText = bodyHtml
           .replacingOccurrences(of: "</p>", with: "\n\n")
           .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

       let decodedText = try Entities.unescape(formattedText)
       return decodedText.trimmingCharacters(in: .whitespacesAndNewlines)
   } catch {
       return "Error parsing HTML"
   }
}
