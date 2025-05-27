//
//  SettingsView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-14.
//

import SwiftUI
import CoreData
import FeedKit
import MessageUI

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject var player = AudioPlayerManager.shared
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State private var podcastCount = 0
    @State private var episodeCount = 0
    @State private var lastSynced: Date? = UserDefaults.standard.object(forKey: "lastCloudSyncDate") as? Date
    @State private var selectedIconName: String = UIApplication.shared.alternateIconName ?? "AppIcon-Green"
    @State private var totalPlayedSeconds: Double = 0
    @State private var subscribedCount: Int = 0
    @State private var playCount: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var currentSpeed: Float = AudioPlayerManager.shared.playbackSpeed
    @State private var currentForwardInterval: Double = AudioPlayerManager.shared.forwardInterval
    @State private var currentBackwardInterval: Double = AudioPlayerManager.shared.backwardInterval
    @State private var allowNotifications = true
    @State private var showDebugTools = false
    @State private var showingMailView = false
    @State private var showMailErrorAlert = false
    @State private var showingAppIcons = false
    @State private var showingUpgrade = false

    private var appTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRawValue) ?? .system }
        set { appThemeRawValue = newValue.rawValue }
    }
    
    var namespace: Namespace.ID
    
    var body: some View {
        ZStack(alignment:.topLeading) {
//            let splashFadeStart: CGFloat = -150
//            let splashFadeEnd: CGFloat = 0
//            let clamped = min(max(scrollOffset, splashFadeStart), splashFadeEnd)
//            let opacity = (clamped - splashFadeStart) / (splashFadeEnd - splashFadeStart) - 0.5
//
//            if isSubscriber {
//                Image("pro-pattern")
//                    .resizable()
//                    .frame(maxWidth:.infinity,maxHeight:500)
//                    .mask(
//                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
//                                       startPoint: .top, endPoint: .bottom)
//                    )
//                    .ignoresSafeArea(.all)
//                    .opacity(opacity)
//                    .transition(.opacity)
//            }
            
            ScrollView {
                Color.clear
                    .frame(height: 1)
                    .trackScrollOffset("scroll") { value in
                        scrollOffset = value
                    }
                
                Spacer().frame(height:32)
                
                VStack {
                    HStack(alignment:.top) {
                        Image(userManager.isSubscriber ? "peapod-plus-mark" : "peapod-mark")
                        
                        Spacer()
                        
                        if userManager.isSubscriber {
                            Text("Manage Subscription")
                                .textDetail()
                        }
                    }
                    .frame(maxWidth:.infinity, alignment:.leading)
                    
                    HStack {
                        VStack(alignment:.leading) {
                            Text(userManager.memberTypeDisplay)
                                .titleCondensed()
                            
                            Text("Since \(userManager.userDateString)")
                                .textDetail()
                        }
                        Spacer()
                        
                        if !userManager.isSubscriber {
                            HStack {
                                let hours = Int(totalPlayedSeconds) / 3600
                                
                                VStack(alignment: .leading) {
                                    Text("\(hours)")
                                        .titleCondensed()
                                        .monospaced()
                                        .contentTransition(.numericText())
                                    
                                    Text("Hours listened")
                                        .textDetail()
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("\(playCount)")
                                        .titleCondensed()
                                        .monospaced()
                                        .contentTransition(.numericText())
                                    
                                    Text("Episodes played")
                                        .textDetail()
                                }
                            }
                        }
                    }
                    .frame(maxWidth:.infinity)
                    
                    if userManager.isSubscriber {
                        HStack {
                            FadeInView(delay:0.5) {
                                VStack(alignment:.leading, spacing: 8) {
                                    let hours = Int(totalPlayedSeconds) / 3600
                                    Image(systemName:"airpods.max")
                                    VStack(alignment:.leading) {
                                        Text("\(hours)")
                                            .titleSerif()
                                            .monospaced()
                                            .contentTransition(.numericText())
                                        
                                        Text("Hours listened")
                                            .textDetail()
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(
                                    LinearGradient(
                                        stops: [
                                            Gradient.Stop(color: .white.opacity(0.3), location: 0.00),
                                            Gradient.Stop(color: .white.opacity(0), location: 1.00),
                                        ],
                                        startPoint: UnitPoint(x: 0, y: 0),
                                        endPoint: UnitPoint(x: 0.5, y: 1)
                                    )
                                )
                                .background(.white.opacity(0.15))
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .inset(by: 1)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                )
                            }
                            
                            FadeInView(delay:0.6) {
                                VStack(alignment:.leading, spacing:8) {
                                    Image(systemName:"play.circle")
                                        .symbolRenderingMode(.hierarchical)
                                    
                                    VStack(alignment:.leading) {
                                        Text("\(playCount)")
                                            .titleSerif()
                                            .monospaced()
                                            .contentTransition(.numericText())
                                        
                                        Text("Episodes played")
                                            .textDetail()
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(
                                    LinearGradient(
                                        stops: [
                                            Gradient.Stop(color: .white.opacity(0.3), location: 0.00),
                                            Gradient.Stop(color: .white.opacity(0), location: 1.00),
                                        ],
                                        startPoint: UnitPoint(x: 0, y: 0),
                                        endPoint: UnitPoint(x: 0.5, y: 1)
                                    )
                                )
                                .background(.white.opacity(0.15))
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .inset(by: 1)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                )
                            }
                        }
                        .frame(maxWidth:.infinity, alignment:.leading)
                        
                        NavigationLink {
                            PPPopover(showBg: true) {
                                ActivityView(namespace: namespace)
                            }
                        } label: {
                            Text("View Stats")
                                .frame(maxWidth:.infinity)
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(hex: "#3CA4F4") ?? .blue,
                                            Color(hex: "#9D93C5") ?? .purple,
                                            Color(hex: "#E98D64") ?? .orange
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .buttonStyle(ShadowButton())
                        
                    } else {
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
                        .sheet(isPresented: $showingUpgrade) {
                            UpgradeView()
                                .modifier(PPSheet())
                                .presentationDetents([.medium])
                        }
                    }
                }
                .foregroundStyle(Color.white)
                .padding()
                .background {
                    if userManager.isSubscriber {
                        GeometryReader { geometry in
                            Color(hex: "#C9C9C9")
                            Image("pro-pattern")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        }
                        .ignoresSafeArea(.all)
                    } else {
                        Color.surface
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius:16))
                
                FadeInView(delay:0.7) {
                    VStack {
                        Text("Settings")
                            .headerSection()
                            .frame(maxWidth:.infinity, alignment: .leading)
                            .padding(.top,24)
                        
                        RowItem(
                            icon: currentSpeed < 0.5 ? "gauge.with.dots.needle.0percent" :
                                  currentSpeed < 0.9 ? "gauge.with.dots.needle.33percent" :
                                  currentSpeed > 1.2 ? "gauge.with.dots.needle.100percent" :
                                  currentSpeed > 1.0 ? "gauge.with.dots.needle.67percent" :
                                  "gauge.with.dots.needle.50percent",
                            label: "Playback Speed") {
                            Menu {
                                let speeds: [Float] = [2.0, 1.5, 1.2, 1.1, 1.0, 0.75]

                                Section(header: Text("Playback Speed")) {
                                    ForEach(speeds, id: \.self) { speed in
                                        Button(action: {
                                            withAnimation {
                                                player.setPlaybackSpeed(speed)
                                            }
                                        }) {
                                            HStack {
                                                if speed == currentSpeed {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(Color.heading)
                                                }
                                                
                                                Text("\(speed, specifier: "%.1fx")")
                                                    .foregroundStyle(Color.heading)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("\(currentSpeed, specifier: "%.1fx")")
                                        .textBody()
                                    
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                            }
                            .onReceive(player.$playbackSpeed) { newSpeed in
                                currentSpeed = newSpeed
                            }
                        }
                        
                        RowItem(icon: "\(String(format: "%.0f", currentBackwardInterval)).arrow.trianglehead.counterclockwise", label: "Skip Backwards") {
                            Menu {
                                let intervals: [Double] = [45,30,15,10,5]

                                Section(header: Text("Skip Backwards Interval")) {
                                    ForEach(intervals, id: \.self) { interval in
                                        Button(action: {
                                            player.setBackwardInterval(interval)
                                        }) {
                                            HStack {
                                                if interval == currentBackwardInterval {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(Color.heading)
                                                }
                                                
                                                Text("\(interval, specifier: "%.0fs")")
                                                    .foregroundStyle(Color.heading)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("\(currentBackwardInterval, specifier: "%.0fs")")
                                        .textBody()
                                    
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                            }
                            .onReceive(player.$backwardInterval) { newBackwardInterval in
                                currentBackwardInterval = newBackwardInterval
                            }
                        }
                        
                        RowItem(icon: "\(String(format: "%.0f", currentForwardInterval)).arrow.trianglehead.clockwise", label: "Skip Forwards") {
                            Menu {
                                let intervals: [Double] = [45,30,15,10,5]

                                Section(header: Text("Skip Forwards Interval")) {
                                    ForEach(intervals, id: \.self) { interval in
                                        Button(action: {
                                            player.setForwardInterval(interval)
                                        }) {
                                            HStack {
                                                if interval == currentForwardInterval {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(Color.heading)
                                                }
                                                
                                                Text("\(interval, specifier: "%.0fs")")
                                                    .foregroundStyle(Color.heading)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("\(currentForwardInterval, specifier: "%.0fs")")
                                        .textBody()
                                    
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                            }
                            .onReceive(player.$forwardInterval) { newForwardInterval in
                                currentForwardInterval = newForwardInterval
                            }
                        }
                        
//                        RowItem(icon: "app.badge", label: "Notifications") {
//                            Toggle(isOn: $allowNotifications) {
//                                Text("Push Notifications")
//                            }
//                            .labelsHidden()
//                        }
                        
                        RowItem(icon: "sparkles.rectangle.stack", label: "Autoplay Next Episode") {
                            Toggle(isOn: $player.autoplayNext) {
                                Text("Autoplay Next Episode")
                            }
                            .tint(.accentColor)
                            .labelsHidden()
                            .symbolRenderingMode(.hierarchical)
                        }
                    }

                    VStack {
                        let themeIcon = appTheme.icon
                        let themeLabel = appTheme.rawValue
                        
                        Text("Appearance")
                            .headerSection()
                            .frame(maxWidth:.infinity, alignment: .leading)
                            .padding(.top,24)
                        
                        RowItem(icon: themeIcon, label: "Theme") {
                            Menu {
                                ForEach(AppTheme.allCases) { theme in
                                    Button(action: {
                                        appThemeRawValue = theme.rawValue
                                    }) {
                                        HStack {
                                            Text(theme.label.capitalized)
                                            Image(systemName:theme.icon)
                                                .symbolRenderingMode(.hierarchical)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(themeLabel.capitalized)
                                        .textBody()
                                    Image(systemName:"chevron.up.chevron.down")
                                }
                            }
                        }
                        
                        RowItem(icon: "app.badge", label: "App Icon")
                            .onTapGesture {
                                showingAppIcons = true
                            }
                            .sheet(isPresented: $showingAppIcons) {
                                AppIconView(selectedIconName: $selectedIconName)
                                    .modifier(PPSheet())
                                    .presentationDetents([.medium])
                            }
                        
                        VStack(alignment:.leading) {
                            Text("About")
                                .headerSection()
                                .frame(maxWidth:.infinity, alignment:.leading)
                                .padding(.top,24)
                            
                            RowItem(icon: "info.circle", label: "Version") {
                                Text("\(Bundle.main.releaseVersionNumber ?? "0") (\(Bundle.main.buildVersionNumber ?? "0"))")
                                    .textBody()
                            }
                            
                            RowItem(icon: "cloud.circle", label: "Synced") {
                                if let lastSynced = lastSynced {
                                    Text("\(lastSynced.formatted(date: .abbreviated, time: .shortened))")
                                        .textBody()
                                } else {
                                    Text("Never")
                                        .textBody()
                                }
                            }
                            
                            Button {
                                if MFMailComposeViewController.canSendMail() {
                                    showingMailView = true
                                } else {
                                    showMailErrorAlert = true
                                }
                            } label: {
                                RowItem(icon: "paperplane.circle", label: "Send Feedback")
                            }
                            .sheet(isPresented: $showingMailView) {
                                MailView(
                                    messageBody: generateSupportMessageBody()
                                )
                            }
                            .alert("Mail not configured", isPresented: $showMailErrorAlert) {
                                Button("OK", role: .cancel) { }
                            } message: {
                                Text("Please set up a Mail account in order to send logs.")
                            }
                            
                            Text("Thanks for taking the time to check out Peapod! This is the podcast app I've wanted for years and I've put a lot of love into building it. I hope that you enjoy using it as much as I do.\n\nIf you'd like to support the ongoing development of an independent podcast app, consider purchasing a subscription. You'll get custom app icons, more listening insights, and my eternal gratitude.\n")
                                .multilineTextAlignment(.leading)
                                .textBody()
                            
                            Text("- Brady")
                                .multilineTextAlignment(.leading)
                                .font(.custom("Bradley Hand", size: 17))
                            
                            if !userManager.isSubscriber {
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
                                .sheet(isPresented: $showingUpgrade) {
                                    UpgradeView()
                                        .modifier(PPSheet())
                                        .presentationDetents([.medium])
                                }
                            }
                            
//                            NavigationLink {
//                                PPPopover(showBg: true) {
//                                    Acknowledgements()
//                                }
//                            } label: {
//                                RowItem(icon: "link.circle", label: "Acknowledgements")
//                            }
                            
                            if _isDebugAssertConfiguration() || showDebugTools {
                                Text("Debug")
                                    .headerSection()
                                    .frame(maxWidth:.infinity, alignment:.leading)
                                    .padding(.top,24)
                                
                                RowItem(icon: "doc.text", label: "Log Storage") {
                                    Text(LogManager.shared.getTotalLogSize())
                                        .textBody()
                                }
                                
                                Button {
                                    LogManager.shared.clearLog()
                                } label: {
                                    RowItem(icon: "trash", label: "Clear Logs", tint: Color.orange)
                                }
                                
                                Button {
                                    LogManager.shared.cleanupOldLogs()
                                } label: {
                                    RowItem(icon: "eraser", label: "Cleanup Old Logs", tint: Color.blue)
                                }
                                
                                Button {
                                    injectTestPodcast()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.diamond")
                                        
                                        Text("Show test feed")
                                            .foregroundStyle(Color.red)
                                            .textBody()
                                    }
                                    .foregroundStyle(Color.red)
                                    .padding(.vertical, 2)
                                }
                                
                                Divider()
                                
                                NavigationLink {
                                    PPPopover(showBg: true) {
                                        OldEpisodes(namespace:namespace)
                                    }
                                } label: {
                                    RowItem(icon: "eraser", label: "Purge old episodes", tint: Color.red)
                                }
                            }
                        }
                        .frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
            }
            .contentMargins(16,for:.scrollContent)
            .coordinateSpace(name: "scroll")
            .maskEdge(.top)
            .maskEdge(.bottom)
            .task {
                await loadStatistics()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                lastSynced = Date()
                UserDefaults.standard.set(lastSynced, forKey: "lastCloudSyncDate")
            }
        }
    }
    
    // MARK: - Statistics Loading
    private func loadStatistics() async {
        let context = PersistenceController.shared.container.viewContext
        
        do {
            // Use the consolidated fetch requests
            let podcasts = try Podcast.totalPodcastCount(in: context)
            let episodes = try Episode.totalEpisodeCount(in: context)
            let playedSeconds = try await Podcast.totalPlayedDuration(in: context)
            let subscribed = try Podcast.totalSubscribedCount(in: context)
            let plays = try Podcast.totalPlayCount(in: context)
            
            // Update state variables
            podcastCount = podcasts
            episodeCount = episodes
            
            // Wait to allow the UI to render with zeros, then animate the updates
            try? await Task.sleep(for: .nanoseconds(1))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut) {
                    totalPlayedSeconds = playedSeconds
                    subscribedCount = subscribed
                    playCount = plays
                }
            }
        } catch {
            print("Error loading statistics: \(error)")
            // Set default values on error
            podcastCount = 0
            episodeCount = 0
            totalPlayedSeconds = 0
            subscribedCount = 0
            playCount = 0
        }
    }
    
    // MARK: - Test Functions
    private func injectTestPodcast() {
        let context = PersistenceController.shared.container.viewContext

        context.perform {
            let testFeedURL = "https://bradyv.github.io/bvfeed.github.io/peapod-test.xml"

            // Delete old if exists
            let fetchRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "feedUrl == %@", testFeedURL)
            if let existing = (try? context.fetch(fetchRequest))?.first {
                context.delete(existing)
                print("🗑️ Deleted existing test podcast")
            }

            // Parse feed
            FeedParser(URL: URL(string: testFeedURL)!).parseAsync { result in
                switch result {
                case .success(let feed):
                    if let rss = feed.rssFeed {
                        DispatchQueue.main.async {
                            let podcast = PodcastLoader.createOrUpdatePodcast(from: rss, feedUrl: testFeedURL, context: context)
                            podcast.isSubscribed = true

                            // 📢 DIAGNOSTIC PRINTS
                            print("FeedKit RSS Title:", rss.title ?? "nil")
                            print("FeedKit RSS iTunes Image:", rss.iTunes?.iTunesImage?.attributes?.href ?? "nil")
                            print("FeedKit RSS Channel Image:", rss.image?.url ?? "nil")
                            print("FeedKit RSS First Item Image:", rss.items?.first?.iTunes?.iTunesImage?.attributes?.href ?? "nil")

                            // 📢 MANUAL ASSIGN
                            let artworkUrl = rss.iTunes?.iTunesImage?.attributes?.href
                                          ?? rss.image?.url
                                          ?? rss.items?.first?.iTunes?.iTunesImage?.attributes?.href

                            podcast.image = artworkUrl

                            print("Assigned podcast.image:", podcast.image ?? "nil")

                            // Save and refresh episodes
                            EpisodeRefresher.refreshPodcastEpisodes(for: podcast, context: context) {
                                if let latest = (podcast.episode as? Set<Episode>)?
                                    .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) })
                                    .first {
                                    toggleQueued(latest)
                                }
                                print("✅ Loaded test feed episodes")
                            }

                            try? context.save()
                        }
                    } else {
                        print("❌ Failed to parse feed")
                    }
                case .failure(let error):
                    print("❌ Feed parsing failed:", error)
                }
            }
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
