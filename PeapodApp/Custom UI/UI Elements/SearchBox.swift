//
//  SearchBox.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct SearchBox: View {
    @State private var showSearch = false
    @Binding var query: String
    var label: String
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    
    // Accept FocusState binding
    var isTextFieldFocused: FocusState<Bool>.Binding
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .resizable()
                    .frame(width: 12, height: 12)
                    .opacity(0.35)

                TextField(label, text: $query)
                    .focused(isTextFieldFocused)  // Use the passed binding
                    .textBody()
                    .onSubmit {
                        onSubmit?()
                    }

                if !query.isEmpty {
                    Button(action: {
                        query = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .clipShape(Capsule())
            .glassEffect()

            if isTextFieldFocused.wrappedValue {
                Button(action: {
                    isTextFieldFocused.wrappedValue = false
                    showSearch.toggle()
                    query = ""
                    onCancel?()
                }) {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.glass)
                .labelStyle(.iconOnly)
            }
        }
    }
}
