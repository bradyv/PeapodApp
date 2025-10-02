//
//  SkeletonItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-10-01.
//

import SwiftUI

struct SkeletonItem: View {
    var width: CGFloat?
    let height: CGFloat
    var cornerRadius: CGFloat?
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius ?? 8)
            .if(width != nil, transform: { $0.frame(width: width)})
            .frame(height: height)
            .if(width == nil, transform: { $0.frame(maxWidth:.infinity)})
            .foregroundStyle(Color.surface)
    }
}

#Preview {
    VStack {
        SkeletonItem(height:16)
    }
    .frame(maxWidth:.infinity)
}
