//
//  SplashView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-23.
//

import SwiftUI
import DotLottie

struct SplashView: View {
    private let animationView = DotLottieAnimation(fileName: "Peapod.white", config: AnimationConfig(autoplay: false, loop: false, mode: .reverse, speed: 1.5))
    
    var body: some View {
        VStack {
            Spacer()
            animationView.view()
                .frame(width: 128, height: 111)
            Spacer()
        }
        .background(Image("launchimage"))
        .ignoresSafeArea(.all)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                animationView.play()
            }
        }
    }
}

#Preview {
    SplashView()
}
