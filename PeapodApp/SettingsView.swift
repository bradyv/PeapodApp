//
//  SettingsView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-14.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State private var podcastCount = 0
    @State private var episodeCount = 0
    @State private var lastSynced: Date? = UserDefaults.standard.object(forKey: "lastCloudSyncDate") as? Date

    private var appTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRawValue) ?? .system }
        set { appThemeRawValue = newValue.rawValue }
    }
    
    var body: some View {
        ScrollView {
            Spacer().frame(height:24)
            FadeInView(delay: 0.2) {
                Text("My Activity")
                    .titleSerif()
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .padding(.leading).padding(.top,24)
            }
//            
//            VStack {
//                RowItem(icon: "paintpalette", label: "Appearance") {
//                    Menu(appTheme.label) {
//                        ForEach(AppTheme.allCases) { theme in
//                            Button(action: {
//                                appThemeRawValue = theme.rawValue
//                            }) {
//                                Label(theme.label, systemImage: theme.icon)
//                            }
//                        }
//                    }
//                    .textBody()
//                }
//            }
//            .padding(.horizontal)
            
            VStack(alignment:.leading) {
                if let lastSynced = lastSynced {
                    Text("Last synced: \(lastSynced.formatted(date: .abbreviated, time: .shortened))")
                        .textDetail()
                } else {
                    Text("Not yet synced")
                        .textDetail()
                }
            }
            .frame(maxWidth:.infinity,alignment:.leading)
            .padding(.horizontal)
            
            ActivityView()
            
            VStack {
                Image("Peapod")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width:32)
                
                Text("Peapod")
                    .fontDesign(.serif)
                
                Text("Version \(Bundle.main.releaseVersionNumber ?? "0") (\(Bundle.main.buildVersionNumber ?? "0"))")
                    .textDetail()
            }
        }
        .maskEdge(.bottom)
        .task {
            let context = PersistenceController.shared.container.viewContext
            podcastCount = (try? context.count(for: Podcast.fetchRequest())) ?? 0
            episodeCount = (try? context.count(for: Episode.fetchRequest())) ?? 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            lastSynced = Date()
            UserDefaults.standard.set(lastSynced, forKey: "lastCloudSyncDate")
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

#Preview {
    SettingsView()
}
