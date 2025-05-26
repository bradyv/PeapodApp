//
//  SubscriptionManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-26.
//

import Foundation

class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    private init() {}
    let tiers = [
        SubscriptionTiers(term: "Monthly", price: "CAD $3.99"),
        SubscriptionTiers(term: "Annual", price: "CAD $35.99")
        
    ]
}

struct SubscriptionTiers {
    var term: String
    var price: String
    
    init(term: String, price: String) {
        self.term = term
        self.price = price
    }
}
