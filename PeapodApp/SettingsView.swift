//
//  SettingsView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-14.
//

import SwiftUI
import CoreData

struct SettingsView: View {
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State private var podcastCount = 0
    @State private var episodeCount = 0
    @State private var lastSynced: Date? = UserDefaults.standard.object(forKey: "lastCloudSyncDate") as? Date
    @State private var selectedIconName: String = UIApplication.shared.alternateIconName ?? "AppIcon"
    @State private var totalPlayedSeconds: Double = 0
    @State private var subscribedCount: Int = 0
    @State private var playCount: Int = 0
    @State private var showActivity = false
    @State private var showAcknowledgements = false

    private var appTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRawValue) ?? .system }
        set { appThemeRawValue = newValue.rawValue }
    }
    private let columns = Array(repeating: GridItem(.flexible(), spacing:8), count: 4)
    
    @State var appIcons = [
        AppIcons(name: "Peapod", asset: "AppIcon-Green"),
        AppIcons(name: "Blueprint", asset: "AppIcon-Blueprint"),
        AppIcons(name: "Pastel", asset: "AppIcon-Pastel"),
        AppIcons(name: "Cupertino", asset: "AppIcon-Cupertino"),
        AppIcons(name: "Pride", asset: "AppIcon-Pride"),
        AppIcons(name: "Coachella", asset: "AppIcon-Coachella"),
        AppIcons(name: "Rinzler", asset: "AppIcon-Rinzler"),
        AppIcons(name: "Clouds", asset: "AppIcon-Clouds"),
    ]
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:24)
            
            VStack(spacing:24) {
                VStack(spacing:4) {
                    Image("Peapod.logo")
                    Text("Peapod")
                        .titleSerif()
                }
                
                HStack {
                    LazyVGrid(columns:Array(repeating: GridItem(.flexible(), spacing:8), count: 3)) {
                        VStack(alignment:.leading, spacing: 8) {
                            let hours = Int(totalPlayedSeconds) / 3600
                            Image(systemName:"airpods.max")
                            VStack(alignment:.leading) {
                                Text("\(hours)")
                                    .titleSerif()
                                    .monospaced()
                                
                                Text("Hours listened")
                                    .textDetail()
                            }
                        }
                        .frame(maxWidth:.infinity,alignment:.leading)
                        
                        VStack(alignment:.leading, spacing:8) {
                            Image(systemName:"heart.text.square")
                            
                            VStack(alignment:.leading) {
                                Text("\(subscribedCount)")
                                    .titleSerif()
                                
                                Text("Subscriptions")
                                    .textDetail()
                            }
                        }
                        .frame(maxWidth:.infinity,alignment:.leading)
                        
                        VStack(alignment:.leading, spacing:8) {
                            Image(systemName:"play.circle")
                            
                            VStack(alignment:.leading) {
                                Text("\(playCount)")
                                    .titleSerif()
                                
                                Text("Episodes played")
                                    .textDetail()
                            }
                        }
                        .frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
                .frame(maxWidth:.infinity, alignment:.leading)
                .padding()
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius:12))
                
                RowItem(icon: "trophy", label: "My Activity")
                    .onTapGesture {
                        showActivity.toggle()
                    }
            }
            .padding(.horizontal)
            
            Text("Appearance")
                .headerSection()
                .frame(maxWidth:.infinity, alignment: .leading)
                .padding(.leading).padding(.top,24)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing:8), count: 3)) {
                ForEach(AppTheme.allCases) { theme in
                    let isSelected = appTheme == theme
                    VStack(alignment:.leading, spacing: 8) {
                        Image(systemName: theme.icon)
                        Text(theme.label)
                            .textBody()
                    }
                    .frame(maxWidth:.infinity, alignment:.leading)
                    .padding()
                    .clipShape(RoundedRectangle(cornerRadius:8))
                    .contentShape(RoundedRectangle(cornerRadius:8))
                    .overlay(
                        RoundedRectangle(cornerRadius:8)
                            .stroke(isSelected ? Color.heading : Color.surface, lineWidth: 2)
                    )
                    .onTapGesture {
                        appThemeRawValue = theme.rawValue
                    }
                }
            }
            .padding(.horizontal)
            
            VStack {
                Text("App Icon")
                    .headerSection()
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .padding(.leading).padding(.top,24)
                
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
                                                selectedIconName = icon.asset
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
                .padding(1)
            }
            .contentMargins(.horizontal,16, for: .scrollContent)
            
            VStack {
                Text("About")
                    .headerSection()
                    .frame(maxWidth:.infinity, alignment:.leading)
                    .padding(.top,24)
                
                RowItem(icon: "info.circle", label: "Version") {
                    Text("\(Bundle.main.releaseVersionNumber ?? "0") (\(Bundle.main.buildVersionNumber ?? "0"))")
                        .textBody()
                }
                
                RowItem(icon: "icloud", label: "Synced") {
                    if let lastSynced = lastSynced {
                        Text("\(lastSynced.formatted(date: .abbreviated, time: .shortened))")
                            .textBody()
                    } else {
                        Text("Never")
                            .textBody()
                    }
                }
                
                RowItem(icon: "hands.clap", label: "Libraries")
                    .onTapGesture {
                        showAcknowledgements.toggle()
                    }
            }
            .padding(.horizontal)
            
            VStack {
                Text("Made in Canada")
                    .textBody()
                
                Text("Built by a cute lil guy with a nose ring.")
                    .textDetail()
                
                Text("Love to Kat, Brad, Dave, and JD for their support and guidance.")
                    .textDetail()
                
                Spacer().frame(height:24)
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.surface)
            }
            .padding(.top,24)
            .padding(.horizontal)
        }
        .background(Color.background)
        .task {
            let context = PersistenceController.shared.container.viewContext
            podcastCount = (try? context.count(for: Podcast.fetchRequest())) ?? 0
            episodeCount = (try? context.count(for: Episode.fetchRequest())) ?? 0
            
            totalPlayedSeconds = (try? await Podcast.totalPlayedDuration(in: context)) ?? 0
            subscribedCount = (try? Podcast.totalSubscribedCount(in: context)) ?? 0
            playCount = (try? Podcast.totalPlayCount(in: context)) ?? 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            lastSynced = Date()
            UserDefaults.standard.set(lastSynced, forKey: "lastCloudSyncDate")
        }
        .sheet(isPresented: $showActivity) {
            ActivityView()
                .modifier(PPSheet())
        }
        .sheet(isPresented: $showAcknowledgements) {
            Acknowledgements()
                .modifier(PPSheet())
        }
    }
}

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

struct AppIcons {

    var name: String
    var asset: String

    init(name: String, asset: String) {
        self.name = name
        self.asset = asset
    }
}

#Preview {
    SettingsView()
}
