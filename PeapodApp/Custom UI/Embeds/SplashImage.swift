//
//  SplashImage.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-27.
//

import SwiftUI
import Kingfisher

struct SplashImage: View {
    @Environment(\.colorScheme) var colorScheme
    let image: String
    
    var body: some View {
        VStack(alignment:.leading) {
            KFImage(URL(string: image))
                .resizable()
                .aspectRatio(1,contentMode:.fit)
                .blur(radius:50)
                .mask(
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                   startPoint: .top, endPoint: .bottom)
                )
                .opacity(colorScheme == .dark ? 0.75 : 1)
            Spacer()
        }
        .frame(maxWidth:.infinity)
        .ignoresSafeArea(.all)
    }
}
