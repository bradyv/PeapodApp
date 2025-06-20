//
//  SplashView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-23.
//

import SwiftUI
import RiveRuntime
import Lottie

struct SplashView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appStateManager: AppStateManager
    @StateObject private var riveModel = RiveViewModel(fileName: "peapod")
    
    var body: some View {
        ZStack {
            Image("launchimage")
                .resizable()
                .aspectRatio(contentMode: .fill)
            
            LottieView(animation: .named("PPMaze2"))
                .playing()
//                .looping()
                .frame(width:100,height:113)
            
        }
        .ignoresSafeArea()
    }
}

#Preview {
    SplashView()
}
