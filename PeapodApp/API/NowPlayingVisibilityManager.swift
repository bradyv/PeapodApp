//
//  NowPlayingVisibilityManager.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-24.
//

import SwiftUI
import Combine

final class NowPlayingVisibilityManager: ObservableObject {
    @Published var isVisible: Bool = true
}
