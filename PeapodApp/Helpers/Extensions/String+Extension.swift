//
//  String+Extension.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-06-25.
//

import Foundation

extension String {
    func normalizeURL() -> String {
        var normalized = self
        
        // Force HTTPS
        normalized = normalized.replacingOccurrences(of: "http://", with: "https://")
        
        // Remove trailing slash
        if normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        
        // Remove common query parameters that don't affect feed content
        if let url = URL(string: normalized),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // Remove tracking parameters but keep important ones
            components.queryItems = components.queryItems?.filter { item in
                !["utm_source", "utm_medium", "utm_campaign", "ref"].contains(item.name)
            }
            normalized = components.url?.absoluteString ?? normalized
        }
        
        return normalized
    }
}
