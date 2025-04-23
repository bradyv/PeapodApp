//
//  Waveform.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-23.
//

import SwiftUI

struct WaveformView: View {
    @Binding var isPlaying: Bool
    var color: Color = .heading

    @State private var levels: [CGFloat] = Array(repeating: 0.5, count: 4)
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 2, height: isPlaying ? levels[i] * 20 : 4)
            }
        }
        .frame(width:18,height: 16)
        .onAppear { if isPlaying { startAnimating() } }
        .onChange(of: isPlaying) { playing in
            playing ? startAnimating() : stopAnimating()
        }
        .onDisappear(perform: stopAnimating)
    }

    private func startAnimating() {
        stopAnimating()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                levels = levels.map { _ in CGFloat.random(in: 0.1...1.0) }
            }
        }
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    @Previewable @State var showWave = false
    WaveformView(isPlaying: $showWave)
}
