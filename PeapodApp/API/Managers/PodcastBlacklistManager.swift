//
//  PodcastBlacklist.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-08-17.
//

import Foundation
import SwiftUI

// MARK: - Remote Configurable Blacklist Manager
class PodcastBlacklist: ObservableObject {
    static let shared = PodcastBlacklist()
    
    @AppStorage("blacklistedPodcastIds") private var storedBlacklistData: Data = Data()
    @AppStorage("blacklistedSearchTerms") private var storedSearchTermsData: Data = Data()
    @AppStorage("blacklistLastUpdated") private var lastUpdated: TimeInterval = 0
    @AppStorage("searchTermsLastUpdated") private var searchTermsLastUpdated: TimeInterval = 0
    
    private var _blacklistedIds: Set<String>?
    private var _blacklistedSearchTerms: Set<String>?
    private let remoteBlacklistURL = "https://bradyv.github.io/bvfeed.github.io/blacklisted-podcasts.json"
    private let remoteSearchTermsURL = "https://bradyv.github.io/bvfeed.github.io/blacklisted-search-terms.json"
    private let cacheExpiryHours: TimeInterval = 24 // Update every 24 hours
    
    private init() {
        // Auto-fetch on init if cache is expired
        if shouldUpdateFromRemote() {
            updateFromRemote()
        }
        if shouldUpdateSearchTermsFromRemote() {
            updateSearchTermsFromRemote()
        }
    }
    
    var blacklistedIds: Set<String> {
        if let cached = _blacklistedIds {
            return cached
        }
        
        // Try to load from UserDefaults
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: storedBlacklistData) {
            _blacklistedIds = decoded
            return decoded
        }
        
        // Fallback to empty set (no hardcoded blacklist)
        _blacklistedIds = Set<String>()
        return Set<String>()
    }
    
    var blacklistedSearchTerms: Set<String> {
        if let cached = _blacklistedSearchTerms {
            return cached
        }
        
        // Try to load from UserDefaults
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: storedSearchTermsData) {
            _blacklistedSearchTerms = decoded
            return decoded
        }
        
        // Fallback to empty set
        _blacklistedSearchTerms = Set<String>()
        return Set<String>()
    }
    
    func isBlacklisted(_ id: String) -> Bool {
        return blacklistedIds.contains(id)
    }
    
    func isBlacklisted(_ trackId: Int) -> Bool {
        return blacklistedIds.contains(String(trackId))
    }
    
    func isSearchTermBlocked(_ searchTerm: String) -> Bool {
        let lowercaseSearch = searchTerm.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        return blacklistedSearchTerms.contains { blockedTerm in
            lowercaseSearch.contains(blockedTerm.lowercased())
        }
    }
    
    private func shouldUpdateFromRemote() -> Bool {
        let now = Date().timeIntervalSince1970
        return (now - lastUpdated) > (cacheExpiryHours * 3600)
    }
    
    private func shouldUpdateSearchTermsFromRemote() -> Bool {
        let now = Date().timeIntervalSince1970
        return (now - searchTermsLastUpdated) > (cacheExpiryHours * 3600)
    }
    
    private func updateBlacklist(_ newList: Set<String>) {
        _blacklistedIds = newList
        if let encoded = try? JSONEncoder().encode(newList) {
            storedBlacklistData = encoded
            lastUpdated = Date().timeIntervalSince1970
        }
        LogManager.shared.info("📛 Updated blacklist with \(newList.count) blocked podcasts")
    }
    
    private func updateSearchTerms(_ newList: Set<String>) {
        _blacklistedSearchTerms = newList
        if let encoded = try? JSONEncoder().encode(newList) {
            storedSearchTermsData = encoded
            searchTermsLastUpdated = Date().timeIntervalSince1970
        }
        LogManager.shared.info("🚫 Updated blocked search terms with \(newList.count) terms")
    }
    
    func updateFromRemote() {
        guard let url = URL(string: remoteBlacklistURL) else { return }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil else {
                LogManager.shared.error("❌ Failed to fetch blacklist: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                // Expect JSON array of strings: ["1535809341", "1438054347", ...]
                let blacklistArray = try JSONDecoder().decode([String].self, from: data)
                DispatchQueue.main.async {
                    self.updateBlacklist(Set(blacklistArray))
                }
            } catch {
                LogManager.shared.error("❌ Failed to decode blacklist JSON: \(error)")
            }
        }.resume()
    }
    
    func updateSearchTermsFromRemote() {
        guard let url = URL(string: remoteSearchTermsURL) else { return }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil else {
                LogManager.shared.error("❌ Failed to fetch search terms blacklist: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                // Expect JSON array of strings: ["joe rogan", "tucker carlson", ...]
                let searchTermsArray = try JSONDecoder().decode([String].self, from: data)
                DispatchQueue.main.async {
                    self.updateSearchTerms(Set(searchTermsArray))
                }
            } catch {
                LogManager.shared.error("❌ Failed to decode search terms blacklist JSON: \(error)")
            }
        }.resume()
    }
    
    // Manual refresh methods
    func forceUpdate(completion: @escaping (Bool) -> Void = { _ in }) {
        updateFromRemote()
        updateSearchTermsFromRemote()
        // Simple completion - in a real app you might want to track the actual success/failure
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            completion(true)
        }
    }
}
