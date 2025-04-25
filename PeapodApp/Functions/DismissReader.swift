//
//  DismissReader.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-24.
//

import SwiftUI

struct DismissReader<Content: View>: View {
  let content: (DismissAction) -> Content
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    content(dismiss)
  }
}

extension View {
  @ViewBuilder
  func readDismiss(_ reader: @escaping (_ dismiss: @escaping () -> Void) -> Void) -> some View {
    background {
      DismissReader { dismiss in
        Color.clear.onAppear {
          reader {
            dismiss()
          }
        }
      }
    }
  }

  @ViewBuilder
  func readDismiss(_ binding: Binding<() -> Void>) -> some View {
    readDismiss { dismiss in
      binding.wrappedValue = dismiss
    }
  }
}
