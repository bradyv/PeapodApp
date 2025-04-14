//
//  SearchBox.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-03.
//

import SwiftUI

struct SearchBox: View {
    @State private var showSearch = false
    @FocusState private var isTextFieldFocused: Bool
    @Binding var query: String
    var label: String
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .resizable()
                    .frame(width: 12, height: 12)
                    .opacity(0.35)

                TextField(label, text: $query)
                    .focused($isTextFieldFocused)
                    .textBody()
                    .onSubmit {
                        onSubmit?()
                    }

                if !query.isEmpty {
                    Button(action: {
                        query = ""
                        isTextFieldFocused = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.surface)
            .clipShape(Capsule())

            Button(action: {
                isTextFieldFocused = false
                showSearch.toggle()
                query = ""
                onCancel?()
            }) {
                Text("Cancel")
            }
            .textBody()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
}
