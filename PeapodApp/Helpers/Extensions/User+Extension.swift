//
//  User+Extension.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-05-02.
//

import Foundation
import CoreData

// Define the enum at file level
enum MemberType: String, Codable {
    case listener = "listener"
    case betaTester = "beta_tester"
    case subscriber = "subscriber"
    
    // You can add helper properties if needed
    var displayName: String {
        switch self {
        case .listener: return "Listener"
        case .betaTester: return "Beta Tester"
        case .subscriber: return "Supporter"
        }
    }
}

// Extend the User class
extension User {
    // Add a computed property for memberType
    var memberType: MemberType? {
        get {
            guard let rawValue = userType else { return nil }
            return MemberType(rawValue: rawValue)
        }
        set {
            userType = newValue?.rawValue
        }
    }
}
