//
//  PPSheet.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-16.
//

import SwiftUI

struct PPSheet: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    
    func body(content: Content) -> some View {
        NavigationStack { 
            content
                .presentationDragIndicator(.hidden)
                .background(Color.background)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button(action: {
                            dismiss()
                        }) {
                            Label("Close", systemImage: "xmark")
                        }
                    }
                }
        }
    }
}
