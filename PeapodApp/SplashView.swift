//
//  SplashView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-23.
//

import SwiftUI
import DotLottie

struct SplashView: View {
    private let animationView = DotLottieAnimation(fileName: "Peapod.white", config: AnimationConfig(autoplay: false, loop: false, mode: .reverse, speed: 1))
    
    var body: some View {
        ZStack {
            Image("launchimage")
                .resizable()
                .aspectRatio(contentMode: .fill)
            
            FadeInView(delay:0.1) {
                animationView.view()
                    .frame(width: 128, height: 111)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
                animationView.play()
            }
        }
    }
}

#Preview {
    SplashView()
}
