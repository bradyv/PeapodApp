//
//  RowItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-14.
//

import SwiftUI

struct RowItem: View {
    let icon: String
    let label: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24, alignment: .center)
                .textBody()
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textBody()
            Image(systemName: "chevron.right")
                .frame(width: 16, alignment: .trailing)
                .textBody()
                .opacity(0.25)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
