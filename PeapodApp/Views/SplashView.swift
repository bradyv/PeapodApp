//
//  SplashView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-23.
//

import SwiftUI
import RiveRuntime

struct SplashView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appStateManager: AppStateManager
    @StateObject private var riveModel = RiveViewModel(fileName: "peapod")
    
    var body: some View {
        ZStack {
            Image("launchimage")
                .resizable()
                .aspectRatio(contentMode: .fill)
            
            RiveViewModel(fileName: "peapod").view()
                .frame(width:128,height:111)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    SplashView()
}
