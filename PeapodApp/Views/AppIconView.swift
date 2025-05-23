//
//  AppIconView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-22.
//

import SwiftUI

struct AppIconView: View {
    @Binding var selectedIconName: String
    @State var appIcons = [
        AppIcons(name: "Peapod", asset: "AppIcon-Green", splash: "Splash-Green"),
        AppIcons(name: "Blueprint", asset: "AppIcon-Blueprint", splash: "Splash-Blueprint"),
        AppIcons(name: "Pastel", asset: "AppIcon-Pastel", splash: "Splash-Pastel"),
        AppIcons(name: "Cupertino", asset: "AppIcon-Cupertino", splash: "Splash-Cupertino"),
        AppIcons(name: "Pride", asset: "AppIcon-Pride", splash: "Splash-Pride"),
        AppIcons(name: "Coachella", asset: "AppIcon-Coachella", splash: "Splash-Coachella"),
        AppIcons(name: "Rinzler", asset: "AppIcon-Rinzler", splash: "Splash-Rinzler"),
        AppIcons(name: "Clouds", asset: "AppIcon-Clouds", splash: "Splash-Clouds"),
    ]
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 4)
    
    var body: some View {
        VStack {
            Spacer().frame(height:24)
            FadeInView(delay: 0.1) {
                HStack {
                    Text("App Icon")
                        .titleSerif()
                    
                    Spacer()
                }
                .padding(.horizontal).padding(.top,24)
            }
            FadeInView(delay: 0.2) {
                LazyVGrid(columns:columns) {
                    ForEach(appIcons, id: \.name) { icon in
                        let isSelected = selectedIconName == icon.asset
                        VStack {
                            ZStack(alignment:.bottomTrailing) {
                                Image(icon.name)
                                    .resizable()
                                    .aspectRatio(1,contentMode: .fit)
                                    .frame(width:64,height:64)
                                    .onTapGesture {
                                        UIApplication.shared.setAlternateIconName(icon.asset == "AppIcon" ? nil : icon.asset) { error in
                                            if let error = error {
                                                print("❌ Failed to switch icon: \(error)")
                                            } else {
                                                print("✅ Icon switched to \(icon.name)")
                                                withAnimation(.easeInOut(duration: 0.5)) {
                                                    selectedIconName = icon.asset  // This now updates the binding
                                                }
                                            }
                                        }
                                    }
                                
                                VStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.heading)
                                }
                                .padding(2)
                                .background(Color.background)
                                .clipShape(Circle())
                                .opacity(isSelected ? 1 : 0)
                                .offset(x:4,y:4)
                            }
                            
                            Text(icon.name)
                                .foregroundStyle(isSelected ? .heading : .text)
                                .textDetail()
                            
                        }
                    }
                }
            }
        }
        .frame(maxHeight:.infinity, alignment:.topLeading)
    }
}
