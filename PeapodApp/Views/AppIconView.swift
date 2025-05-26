//
//  AppIconView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-22.
//

import SwiftUI

struct AppIconView: View {
    @Binding var selectedIconName: String
    @State private var showingUpgrade = false
    private var appIcons: [AppIcons] {
        return AppIconManager.shared.availableIcons
    }
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 4)
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \User.userSince, ascending: true)],
        animation: .default)
    private var users: FetchedResults<User>
    
    // Convenience computed property to get the user (first and likely only one)
    private var user: User? {
        return users.first
    }
    
    private var isSubscriber: Bool {
        return user?.memberType == .subscriber
    }
    
    var body: some View {
        VStack {
            Spacer().frame(height:24)
            
            Text("App Icon")
                .titleSerif()
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(.top,24)
            
            LazyVGrid(columns:columns) {
                ForEach(appIcons, id: \.name) { icon in
                    let isSelected = selectedIconName == icon.asset
                    
                    Button(action: {
                        if isSubscriber {
                            UIApplication.shared.setAlternateIconName(icon.asset == "AppIcon-Green" ? nil : icon.asset) { error in
                                if let error = error {
                                    print("❌ Failed to switch icon: \(error)")
                                } else {
                                    print("✅ Icon switched to \(icon.name)")
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        selectedIconName = icon.asset
                                    }
                                }
                            }
                        } else {
                            showingUpgrade = true
                        }
                    }) {
                        VStack {
                            ZStack(alignment:.bottomTrailing) {
                                Image(icon.name)
                                    .resizable()
                                    .aspectRatio(1,contentMode: .fit)
                                    .frame(width:64,height:64)
                                
                                VStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.heading)
                                }
                                .padding(2)
                                .background(Color.background)
                                .clipShape(Circle())
                                .opacity(isSelected ? 1 : 0)
                                .offset(x:4,y:4)
                                
                                VStack {
                                    Image(systemName: "lock.circle.fill")
                                        .foregroundStyle(Color.heading)
                                }
                                .padding(2)
                                .background(Color.background)
                                .clipShape(Circle())
                                .opacity(isSubscriber ? 0 : 1)
                                .offset(x:4,y:4)
                            }
                            
                            Text(icon.name)
                                .foregroundStyle(isSelected ? .heading : .text)
                                .textDetail()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
//            .disabled(!isSubscriber)
        
            if !isSubscriber {
                Spacer().frame(height:24)
                Text("Support the ongoing development of an independent podcast app. You’ll get custom app icons, more listening insights, and my eternal gratitude.")
                    .textBody()
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    showingUpgrade = true
                }) {
                    Text("Become a Supporter")
                        .frame(maxWidth:.infinity)
                }
                .buttonStyle(PPButton(
                    type:.filled,
                    colorStyle:.monochrome,
                    peapodPlus: true
                ))
            }
        }
        .frame(maxHeight:.infinity, alignment:.topLeading)
        .padding(.horizontal)
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView()
                .modifier(PPSheet())
                .presentationDetents([.medium])
        }
    }
}
