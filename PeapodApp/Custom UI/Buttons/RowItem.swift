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
    var framedIcon: Bool = false
    @ViewBuilder var accessory: () -> Accessory

    init(icon: String, label: String, tint: Color = Color.text, framedIcon: Bool = false, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.icon = icon
        self.label = label
        self.tint = tint
        self.framedIcon = framedIcon
        self.accessory = accessory
    }

    var body: some View {
        let tint = tint ?? .text
        
        VStack {
            HStack(spacing: 8) {
                if framedIcon {
                    VStack {
                        Image(systemName: icon)
                            .font(.system(size:17))
                            .foregroundStyle(.white)
                    }
                    .frame(width:30,height:30)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius:8))
                } else {
                    Image(systemName: icon)
                        .frame(width: 24)
                        .foregroundStyle(tint)
                        .textBody()
                        .symbolRenderingMode(.hierarchical)
                }
                Text(label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(framedIcon ? Color.text : tint)
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
