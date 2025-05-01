//
//  SpeedView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-30.
//

import SwiftUI

struct SpeedView: View {
    @ObservedObject var player = AudioPlayerManager.shared
    @State private var currentSpeed: Float = AudioPlayerManager.shared.playbackSpeed
    
    var body: some View {
//        let speeds: [Float] = [2.0, 1.5, 1.4, 1.3, 1.2, 1.1, 1.0, 0.9, 0.8, 0.7, 0.6, 0.5]
        let speeds: [Float] = [0.25, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 2.0]
        
        VStack {
            HStack {
                Text("Playback Speed")
                    .headerSection()
                
                Image(systemName:
                    currentSpeed < 0.6 ? "gauge.with.dots.needle.0percent" :
                    currentSpeed < 0.8 ? "gauge.with.dots.needle.33percent" :
                    currentSpeed > 1.4 ? "gauge.with.dots.needle.100percent" :
                    currentSpeed > 1.2 ? "gauge.with.dots.needle.67percent" :
                    "gauge.with.dots.needle.50percent"
                )
                .shadow(color: currentSpeed != 1.0 ? Color.accentColor.opacity(0.5) : Color.clear, radius: 8)
                .foregroundStyle(currentSpeed != 1.0 ? Color.accentColor : Color.heading)
            }
            .frame(maxWidth:.infinity)
            .padding(.vertical)
            .background(.thinMaterial)
            
            Spacer().frame(height:16)
            HStack {
                Button(action: {
                    withAnimation {
                        if let currentIndex = speeds.firstIndex(of: currentSpeed),
                           currentIndex > 0 {
                            let newSpeed = speeds[currentIndex - 1]
                            player.setPlaybackSpeed(newSpeed)
                        }
                    }
                }) {
                    Label("Slower", systemImage: "minus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.hierarchical)
                
                Text("\(currentSpeed, specifier: "%.1fx")")
                    .titleCondensed()
                
                Button(action: {
                    withAnimation {
                        if let currentIndex = speeds.firstIndex(of: currentSpeed),
                           currentIndex < speeds.count - 1 {
                            let newSpeed = speeds[currentIndex + 1]
                            player.setPlaybackSpeed(newSpeed)
                        }
                    }
                }) {
                    Label("faster", systemImage: "plus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.hierarchical)
            }
            
            ZStack {
                Capsule()
                    .fill(Color.surface)
                    .frame(maxWidth:.infinity)
                    .frame(height:3)
                    .maskEdge(.leading)
                    .maskEdge(.trailing)
                
                HStack {
                    ForEach(speeds, id: \.self) { speed in
                        VStack {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width:speed == currentSpeed ? 16 : 2,height:speed == currentSpeed ? 16 : 12)
                                .background(speed == currentSpeed ? Color.accentColor : Color.surface)
                                .if(speed == currentSpeed, transform: {
                                    $0.clipShape(Circle())
                                })
                                .onTapGesture {
                                    player.setPlaybackSpeed(speed)
                                }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth:.infinity)
            .padding(.horizontal)
            
            HStack {
                Text("0.25x")
                    .textDetail()
                
                Spacer()
                
                Text("2.0x")
                    .textDetail()
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .frame(maxHeight:.infinity)
        .onReceive(player.$playbackSpeed) { newSpeed in
            currentSpeed = newSpeed
        }
    }
}

#Preview {
    SpeedView()
}
