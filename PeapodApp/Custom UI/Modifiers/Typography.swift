//
//  Typography.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-16.
//

import SwiftUI
import UIKit

extension View {
    func typography(size: CGFloat, weight: Font.Weight = .regular, color: Color = .heading) -> some View {
        self.font(.system(size: size, weight: weight)).foregroundColor(color)
    }
}

struct TextStyle: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight = .regular
    var color: Color = .heading
    
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight)).foregroundColor(color)
    }
}

extension View {
    func titleSerif() -> some View { self.typography(size: 34, weight: .regular).fontDesign(.serif) }
    func titleSerifSm() -> some View { self.typography(size: 28, weight: .regular).fontDesign(.serif) }
    func titleSerifMini() -> some View { self.typography(size: 20, weight: .regular).fontDesign(.serif) }
    func titleCondensed() -> some View { self.typography(size: 20, weight: .regular).fontWidth(.condensed) }
    func headerSection() -> some View { self.typography(size: 17, weight: .medium).fontWidth(.condensed) }
    func textBody() -> some View { self.typography(size: 17, color: .text).fontWidth(.condensed) }
    func textBodyEmphasis() -> some View { self.typography(size: 17, weight: .medium, color: .text).fontWidth(.condensed) }
    func textButton() -> some View { self.typography(size: 17, weight: .medium, color: .heading).fontWidth(.condensed) }
    func textDetailEmphasis() -> some View { self.modifier(TextStyle(size: 14, weight: .medium)).fontWidth(.condensed) }
    func textDetail() -> some View { self.modifier(TextStyle(size: 14, color: .text)).fontWidth(.condensed) }
    func textMini() -> some View { self.modifier(TextStyle(size: 13, color: .text)).fontWidth(.condensed) }
}

final class AppAppearance {
    static func setupAppearance() {
        let navigationBarAppearance = UINavigationBarAppearance()
        
        // Set large title font
        navigationBarAppearance.largeTitleTextAttributes = [
            .font: UIFont(descriptor:
                           UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
                           .withDesign(.serif)!, size: 34)
        ]
        
        navigationBarAppearance.titleTextAttributes = [
            .font: UIFont(descriptor:
                            UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
                            .withDesign(.serif)!, size: 17)
        ]
        
        // Apply appearance to all navigation bars
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
    }
}
