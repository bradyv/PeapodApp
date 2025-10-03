//
//  SkeletonItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-10-01.
//

import SwiftUI

struct SkeletonItem: View {
    var width: CGFloat?
    var height: CGFloat?
    var cornerRadius: CGFloat?
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius ?? 8)
            .if(width != nil, transform: { $0.frame(width: width)})
            .if(height != nil, transform: { $0.frame(height: height)})
            .if(height == nil && width == nil, transform: { $0.aspectRatio(1, contentMode:.fill) })
            .foregroundStyle(Color.surface)
    }
}

#Preview {
//    VStack {
//        SkeletonItem(height:16)
//    }
//    .frame(maxWidth:.infinity)
    
    HStack(spacing: 16) {
        // Artwork
        SkeletonItem(width:100, height:100, cornerRadius:24)
        
        // Episode Meta
        VStack(alignment: .leading, spacing: 8) {
            // Podcast Title + Release
            HStack {
                SkeletonItem(width:100, height:16, cornerRadius:4)
                
                SkeletonItem(width:50, height:14, cornerRadius:4)
            }
            
            // Episode Title + Description
            VStack(alignment: .leading, spacing: 2) {
                SkeletonItem(width:200, height:20, cornerRadius:4)
                
                SkeletonItem(height:16, cornerRadius:4)
                
                SkeletonItem(height:16, cornerRadius:4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
