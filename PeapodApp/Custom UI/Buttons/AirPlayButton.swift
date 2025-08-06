//
//  AirPlayButton.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-17.
//

import SwiftUI
import AVKit
import MediaPlayer

struct AirPlayButton: View {
    @State private var currentRouteIcon: String = "airplay.audio" // Default icon
    private let routePickerView = AVRoutePickerView()

    var body: some View {
        ZStack {
            // Custom button showing the correct icon
            Button(action: {
                showRoutePicker()
            }) {
                Image(systemName: currentRouteIcon)
            }
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)
//            .buttonStyle(PPGlassButton(iconOnly:true))
//            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))

            // Keep AVRoutePickerView in the view hierarchy, hidden but functional
            UIViewRepresentableWrapper(view: routePickerView)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .onAppear {
            updateAudioRouteIcon()
            NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
                updateAudioRouteIcon()
            }
        }
    }

    /// Opens the AirPlay menu
    private func showRoutePicker() {
        DispatchQueue.main.async {
            for view in routePickerView.subviews {
                if let button = view as? UIButton {
                    button.sendActions(for: .touchUpInside) // Trigger the system menu
                    return
                }
            }
        }
    }

    // Updates the button icon based on the current audio output
    private func updateAudioRouteIcon() {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute

        if let output = currentRoute.outputs.first(where: { $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE || $0.portType == .bluetoothHFP }) {
            let portName = output.portName.lowercased()
            if portName.contains("airpods pro") {
                currentRouteIcon = "airpods.pro"
            } else if portName.contains("airpods max") {
                currentRouteIcon = "airpods.max"
            } else if portName.contains("airpods") {
                // Gen 1, 2, or 3 — hard to distinguish, so handle Gen 3 by default here
                currentRouteIcon = "airpods.gen3"
            } else {
                currentRouteIcon = "airplay.audio"
            }
        } else if currentRoute.outputs.contains(where: { $0.portType == .headphones || $0.portType == .headsetMic }) {
            currentRouteIcon = "headphones"
        } else {
            currentRouteIcon = "airplay.audio"
        }
    }
}

// Helper to embed a UIKit view in SwiftUI
struct UIViewRepresentableWrapper<T: UIView>: UIViewRepresentable {
    let view: T
    func makeUIView(context: Context) -> T { view }
    func updateUIView(_ uiView: T, context: Context) {}
}
