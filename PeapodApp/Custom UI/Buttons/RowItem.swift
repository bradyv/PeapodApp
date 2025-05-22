//
//  RowItem.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-14.
//

import SwiftUI

struct RowItem<Accessory: View>: View {
    let icon: String
    let label: String
    let tint: Color?
    @ViewBuilder var accessory: () -> Accessory

    init(icon: String, label: String, tint: Color = Color.text, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.icon = icon
        self.label = label
        self.tint = tint
        self.accessory = accessory
    }

    var body: some View {
        let tint = tint ?? .text
        
        VStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(tint)
                    .textBody()
                    .symbolRenderingMode(.hierarchical)
                Text(label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(tint)
                    .textBody()
                if Accessory.self == EmptyView.self {
                    Image(systemName: "chevron.right")
                        .frame(width: 16, alignment: .trailing)
                        .textBody()
                        .opacity(0.25)
                } else {
                    accessory()
                        .frame(alignment: .trailing)
                }
            }
            .padding(.vertical, 2)
            Divider()
        }
        .contentShape(Rectangle())
    }

    private var accessoryIsEmpty: Bool {
        Accessory.self == EmptyView.self
    }
}
