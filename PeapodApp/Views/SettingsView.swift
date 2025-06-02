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
import UserNotifications

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject var player = AudioPlayerManager.shared
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @AppStorage("appNotificationsEnabled") private var appNotificationsEnabled: Bool = false
    @State private var systemNotificationsGranted: Bool = false
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var showNotificationAlert = false
    @State private var showNotificationRequest = false
    @State private var statistics = AppStatistics(podcastCount: 0, episodeCount: 0, totalPlayedSeconds: 0, subscribedCount: 0, playCount: 0)
    @State private var lastSynced: Date? = UserDefaults.standard.object(forKey: "lastCloudSyncDate") as? Date
    @State private var selectedIconName: String = UIApplication.shared.alternateIconName ?? "AppIcon-Green"
    @State private var scrollOffset: CGFloat = 0
    @State private var currentSpeed: Float = AudioPlayerManager.shared.playbackSpeed
    @State private var currentForwardInterval: Double = AudioPlayerManager.shared.forwardInterval
    @State private var currentBackwardInterval: Double = AudioPlayerManager.shared.backwardInterval
    @State private var showDebugTools = false
    @State private var showMailErrorAlert = false
    @State private var activeSheet: SheetType?
    
    enum SheetType: Identifiable {
        case upgrade
        case stats
        case appIcons
        case mail
        
        var id: Int {
            switch self {
            case .upgrade: return 0
            case .stats: return 1
            case .appIcons: return 2
            case .mail: return 3
            }
        }
    }

    private var appTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRawValue) ?? .system }
        set { appThemeRawValue = newValue.rawValue }
    }
    
    var namespace: Namespace.ID
    
    var body: some View {
        ZStack(alignment:.topLeading) {
            ScrollView {
                Color.clear
                    .frame(height: 1)
                    .trackScrollOffset("scroll") { value in
                        scrollOffset = value
                    }
                
                Spacer().frame(height:32)
                
                VStack {
                    let hours = Int(statistics.totalPlayedSeconds) / 3600
                    let hourString = hours > 1 ? "Hours" : "Hour"
                    let episodeString = statistics.playCount > 1 ? "Episodes" : "Episode"
                    
                    HStack(alignment:.top) {
                        Image(userManager.isSubscriber ? "peapod-plus-mark" : "peapod-mark-adaptive")
                        
                        Spacer()
                        
//                        if userManager.isSubscriber {
//                            Text("Manage Subscription")
//                                .foregroundStyle(Color.white)
//                                .textDetail()
//                        }
                    }
                    .frame(maxWidth:.infinity, alignment:.leading)
                    
                    HStack {
                        VStack(alignment:.leading) {
                            Text(userManager.memberTypeDisplay)
                                .foregroundStyle(userManager.isSubscriber ? Color.white : Color.heading)
                                .titleCondensed()
                            
                            Text("Since \(userManager.userDateString)")
                                .foregroundStyle(userManager.isSubscriber ? Color.white : Color.heading)
                                .textDetail()
                        }
                        
                        Spacer()
                        
                        if !userManager.isSubscriber {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(hours)")
                                        .titleCondensed()
                                        .monospaced()
                                        .contentTransition(.numericText())
                                    
                                    Text("\(hourString) listened")
                                        .textDetail()
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("\(statistics.playCount)")
                                        .titleCondensed()
                                        .monospaced()
                                        .contentTransition(.numericText())
                                    
                                    Text("\(episodeString) played")
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
                                    Image(systemName:"airpods.max")
                                        .foregroundStyle(Color.white)
                                    
                                    VStack(alignment:.leading) {
                                        Text("\(hours)")
                                            .foregroundStyle(Color.white)
                                            .titleSerif()
                                            .monospaced()
                                            .contentTransition(.numericText())
                                        
                                        Text("\(hourString) listened")
                                            .foregroundStyle(Color.white)
                                            .textDetail()
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(cardBackgroundGradient)
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
                                        .foregroundStyle(Color.white)
                                        .symbolRenderingMode(.hierarchical)
                                    
                                    VStack(alignment:.leading) {
                                        Text("\(statistics.playCount)")
                                            .foregroundStyle(Color.white)
                                            .titleSerif()
                                            .monospaced()
                                            .contentTransition(.numericText())
                                        
                                        Text("Episodes played")
                                            .foregroundStyle(Color.white)
                                            .textDetail()
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(cardBackgroundGradient)
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
                        
                        Button(action: {
                            activeSheet = .stats
                        }) {
                            Text("View Stats")
                                .frame(maxWidth:.infinity)
                                .foregroundStyle(statsButtonGradient)
                        }
                        .buttonStyle(ShadowButton())
                        
                    } else {
                        Button(action: {
                            activeSheet = .upgrade
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
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(userManager.isSubscriber ? Color.border : Color.clear, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius:16))
                
                FadeInView(delay:0.7) {
                    VStack {
                        Text("Settings")
                            .headerSection()
                            .frame(maxWidth:.infinity, alignment: .leading)
                            .padding(.top,24)
                        
                        RowItem(
                            icon: playbackSpeedIcon,
                            label: "Playback Speed",
                            tint: Color.green,
                            framedIcon: true) {
                                if userManager.isSubscriber {
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
                                } else {
                                    HStack {
                                        Text("\(currentSpeed, specifier: "%.1fx")")
                                            .textBody()
                                        
                                        Image(systemName: "chevron.up.chevron.down")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .onTapGesture {
                                        activeSheet = .upgrade
                                    }
                                }
                        }
                        
                        RowItem(
                            icon: backwardIntervalIcon,
                            label: "Skip Backwards",
                            tint: Color.blue,
                            framedIcon: true) {
                            if userManager.isSubscriber {
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
                            } else {
                                HStack {
                                    Text("\(currentBackwardInterval, specifier: "%.0fs")")
                                        .textBody()
                                    
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .onTapGesture {
                                    activeSheet = .upgrade
                                }
                            }
                        }
                        
                        RowItem(
                            icon: forwardIntervalIcon,
                            label: "Skip Forwards",
                            tint: Color.blue,
                            framedIcon: true) {
                            if userManager.isSubscriber {
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
                            } else {
                                HStack {
                                    Text("\(currentForwardInterval, specifier: "%.0fs")")
                                        .textBody()
                                    
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .onTapGesture {
                                    activeSheet = .upgrade
                                }
                            }
                        }
                        
                        RowItem(
                            icon: "sparkles.rectangle.stack",
                            label: "Autoplay Next Episode",
                            tint: Color.orange,
                            framedIcon: true) {
                            Toggle(isOn: $player.autoplayNext) {
                                Text("Autoplay Next Episode")
                            }
                            .tint(.accentColor)
                            .labelsHidden()
                            .symbolRenderingMode(.hierarchical)
                        }
                        
                        RowItem(
                            icon: "bell",
                            label: "Notifications",
                            tint: Color.red,
                            framedIcon: true) {
                            Toggle(isOn: Binding(
                                get: {
                                    systemNotificationsGranted && appNotificationsEnabled
                                },
                                set: { newValue in
                                    handleNotificationToggle(newValue)
                                }
                            )) {
                                Text("Notifications")
                            }
                            .tint(.accentColor)
                            .labelsHidden()
                        }
                    }

                    VStack {
                        let themeIcon = appTheme.icon
                        let themeLabel = appTheme.rawValue
                        
                        Text("Appearance")
                            .headerSection()
                            .frame(maxWidth:.infinity, alignment: .leading)
                            .padding(.top,24)
                        
                        RowItem(
                            icon: themeIcon,
                            label: "Theme",
                            tint: Color.cyan,
                            framedIcon: true) {
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
                        
                        RowItem(
                            icon: "app.badge",
                            label: "App Icon",
                            tint: Color.cyan,
                            framedIcon: true)
                            .onTapGesture {
                                activeSheet = .appIcons
                            }
                        
                        VStack(alignment:.leading) {
                            Text("About")
                                .headerSection()
                                .frame(maxWidth:.infinity, alignment:.leading)
                                .padding(.top,24)
                            
                            RowItem(
                                icon: "info.circle",
                                label: "Version",
                                tint: Color.gray,
                                framedIcon: true) {
                                Text("\(Bundle.main.releaseVersionNumber ?? "0") (\(Bundle.main.buildVersionNumber ?? "0"))")
                                    .textBody()
                            }
                            
                            RowItem(
                                icon: "cloud.circle",
                                label: "Synced",
                                tint: Color.gray,
                                framedIcon: true) {
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
                                    activeSheet = .mail
                                } else {
                                    showMailErrorAlert = true
                                }
                            } label: {
                                RowItem(
                                    icon: "paperplane.circle",
                                    label: "Send Feedback",
                                    tint: Color.gray,
                                    framedIcon: true)
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
                                    activeSheet = .upgrade
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
                                    subscribeViaURL(feedUrl: "https://bradyv.github.io/bvfeed.github.io/peapod-test.xml")
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
            .sheet(item: $activeSheet) { sheetType in
                switch sheetType {
                case .upgrade:
                    UpgradeView()
                        .modifier(PPSheet())
                case .stats:
                    ActivityView(namespace: namespace)
                        .modifier(PPSheet())
                case .appIcons:
                    AppIconView(selectedIconName: $selectedIconName)
                        .modifier(PPSheet())
                case .mail:
                    MailView(
                        messageBody: generateSupportMessageBody()
                    )
                }
            }
            .onAppear {
                checkNotificationStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                checkNotificationStatus()
            }
            .alert("Enable Notifications", isPresented: $showNotificationAlert) {
                Button("Settings") {
                    openNotificationSettings()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("To receive notifications, please enable them in your device Settings.")
            }
            .sheet(isPresented: $showNotificationRequest) {
                RequestNotificationsView(
                    onComplete: {
                        showNotificationRequest = false
                        // Refresh status after permission request
                        checkNotificationStatus()
                    },
                    namespace: namespace
                )
            }
        }
    }
    
    private var statsButtonGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(hex: "#3CA4F4") ?? .blue,
                Color(hex: "#9D93C5") ?? .purple,
                Color(hex: "#E98D64") ?? .orange
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var playbackSpeedIcon: String {
        if currentSpeed < 0.5 {
            return "gauge.with.dots.needle.0percent"
        } else if currentSpeed < 0.9 {
            return "gauge.with.dots.needle.33percent"
        } else if currentSpeed > 1.2 {
            return "gauge.with.dots.needle.100percent"
        } else if currentSpeed > 1.0 {
            return "gauge.with.dots.needle.67percent"
        } else {
            return "gauge.with.dots.needle.50percent"
        }
    }
    
    private var backwardIntervalIcon: String {
        return "\(String(format: "%.0f", currentBackwardInterval)).arrow.trianglehead.counterclockwise"
    }
    
    private var forwardIntervalIcon: String {
        return "\(String(format: "%.0f", currentForwardInterval)).arrow.trianglehead.clockwise"
    }
    
    // MARK: - Statistics Loading
    private func loadStatistics() async {
        let context = PersistenceController.shared.container.viewContext
        
        do {
            let newStats = try await AppStatistics.load(from: context)
            
            // Wait to allow the UI to render with zeros, then animate the updates
            try? await Task.sleep(for: .nanoseconds(1))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut) {
                    statistics = newStats
                }
            }
        } catch {
            print("Error loading statistics: \(error)")
            // Keep default zero values on error
        }
    }
    
    // MARK: - Notification Methods
    
    private func handleNotificationToggle(_ enabled: Bool) {
        if enabled {
            // User wants to enable notifications
            if systemNotificationsGranted {
                // System permission already granted, just enable in app
                appNotificationsEnabled = true
            } else if notificationAuthStatus == .notDetermined {
                // Never asked before, show our request view
                showNotificationRequest = true
            } else {
                // User previously denied, send them to Settings
                showNotificationAlert = true
            }
        } else {
            // User wants to disable notifications in app
            appNotificationsEnabled = false
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let wasGranted = systemNotificationsGranted
                systemNotificationsGranted = (settings.authorizationStatus == .authorized)
                notificationAuthStatus = settings.authorizationStatus
                
                // If user just enabled notifications in system settings, enable in app too
                if !wasGranted && systemNotificationsGranted {
                    appNotificationsEnabled = true
                }
            }
        }
    }
    
    private func openNotificationSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
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
