//
//  SettingsView.swift
//  Peapod
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
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @EnvironmentObject var player: AudioPlayerManager
    @AppStorage("appNotificationsEnabled") private var appNotificationsEnabled: Bool = false
    @State private var systemNotificationsGranted: Bool = false
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var showNotificationAlert = false
    @State private var showNotificationRequest = false
    @State private var statistics = AppStatistics(podcastCount: 0, totalPlayedSeconds: 0, subscribedCount: 0, playCount: 0)
    @State private var lastSynced: Date? = UserDefaults.standard.object(forKey: "lastCloudSyncDate") as? Date
    @State private var scrollOffset: CGFloat = 0
    @State private var currentSpeed: Float = AudioPlayerManager.shared.playbackSpeed
    @State private var currentForwardInterval: Double = AudioPlayerManager.shared.forwardInterval
    @State private var currentBackwardInterval: Double = AudioPlayerManager.shared.backwardInterval
    @State private var showDebugTools = false
    @State private var showMailErrorAlert = false
    @State private var activeSheet: SheetType?
    @State private var selectedEpisodeForNavigation: Episode? = nil
    @StateObject private var userManager = UserManager.shared
    
    enum SheetType: Identifiable {
        case upgrade
        case mail
        
        var id: Int {
            switch self {
            case .upgrade: return 0
            case .mail: return 1
            }
        }
    }
    
    var body: some View {
        ScrollView {
            Color.clear
                .frame(height: 1)
                .trackScrollOffset("scroll") { value in
                    scrollOffset = value
                }
            
            VStack(spacing:24) {
                userStatsSection
                settingsSection
                aboutSection
                debugSection
                footerSection
            }
        }
        .toolbar {
            if !episodesViewModel.queue.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    MiniPlayer()
                    Spacer()
                    MiniPlayerButton()
                }
            }
        }
        .background(Color.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .contentMargins(16,for:.scrollContent)
        .coordinateSpace(name: "scroll")
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
                    checkNotificationStatus()
                }
            )
        }
    }
}

// MARK: - View Sections
extension SettingsView {
    
    @ViewBuilder
    private var userStatsSection: some View {
        VStack(alignment:.leading) {
            if userManager.hasPremiumAccess {
                ActivityView(mini:true)
            } else {
                HStack(spacing:28) {
                    VStack(alignment:.leading,spacing:10) {
                        SkeletonItem(width:44, height:8)
                        VStack(alignment:.leading,spacing:4) {
                            SkeletonItem(width:68, height:24)
                            SkeletonItem(width:33, height:12)
                        }
                    }
                    .fixedSize()
                    
                    VStack(alignment:.leading,spacing:10) {
                        SkeletonItem(width:44, height:8)
                        SkeletonItem(width:40, height:40)
                    }
                    .fixedSize()
                    
                    WeeklyListeningLineChart(
                        weeklyData: WeeklyListeningLineChart.mockData,
                        favoriteDayName: "Friday",
                        mini: true
                    )
                    .frame(maxWidth:.infinity)
                }
                .frame(maxWidth:.infinity, alignment:.leading)
            }
            
            Spacer().frame(height:16)
            
            moreStatsButton
        }
        .padding()
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius:26))
    }
    
    @ViewBuilder
    private var moreStatsButton: some View {
//        if userManager.hasPremiumAccess || {
//                #if DEBUG
//                true
//                #else
//                false
//                #endif
//            }() {
        if userManager.hasPremiumAccess {
            NavigationLink {
                ActivityView()
            } label: {
                Text("View More")
            }
            .buttonStyle(.glass)
        } else {
            Button {
                activeSheet = .upgrade
            } label: {
                Label("Unlock Stats", systemImage: "fill.lock")
            }
            .buttonStyle(.glassProminent)
        }
    }
    
    @ViewBuilder
    private var settingsSection: some View {
        FadeInView(delay:0.2) {
            VStack {
                playbackSpeedRow
                skipBackwardRow
                skipForwardRow
                autoplayRow
            }
            .padding()
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius:26))
            
            VStack {
                IconSwitcherView()
                notificationsRow
            }
            .padding()
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius:26))
        }
    }
    
    @ViewBuilder
    private var aboutSection: some View {
        FadeInView(delay:0.3) {
            VStack(alignment:.leading) {
                Text("Thanks so much for taking a peek at Peapod! This app has been a little dream I've been nurturing for years that I'm finally sharing with the world. I've poured tons of love into designing and building my ideal podcast app.\n")
                    .multilineTextAlignment(.leading)
                    .textBody()
                
                Image("bv")
                    .renderingMode(.template)
                    .foregroundStyle(.text)
                
                Divider()
                
                feedbackButton
            }
            .padding()
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius:26))
        }
    }
    
    @ViewBuilder
    private var supporterButton: some View {
        if !userManager.hasPremiumAccess {
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
    
    @ViewBuilder
    private var feedbackButton: some View {
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
                framedIcon: true,
                showDivider: false)
        }
        .alert("Mail not configured", isPresented: $showMailErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please set up a Mail account in order to send logs.")
        }
    }
    
    @ViewBuilder
    private var debugSection: some View {
        if _isDebugAssertConfiguration() || showDebugTools {
            FadeInView(delay:0.5) {
                VStack {
                    Button("🧹 Wipe Sync Data") {
                        quickWipeSyncData()
                    }
                    
                    RowItem(icon: "doc.text", label: "Log Storage") {
                        Text(LogManager.shared.getTotalLogSize())
                            .textBody()
                    }
                    
                    Button {
                        LogManager.shared.clearLog()
                    } label: {
                        RowItem(icon: "trash", label: "Clear Today's Logs", tint: Color.orange)
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
                }
                .padding()
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius:26))
            }
            .frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    
    @ViewBuilder
    private var footerSection: some View {
        FadeInView(delay:0.4) {
            VStack {
                supporterButton
                
                Image("peapod-mark")
                    .resizable()
                    .frame(width:58, height:44)
                    .onTapGesture(count: 5) {
                        showDebugTools.toggle()
                    }
                
                Text("Peapod")
                    .titleSerifMini()
                
                Text("\(Bundle.main.releaseVersionNumber ?? "0") (\(Bundle.main.buildVersionNumber ?? "0"))")
                    .textDetail()
            }
        }
    }
}

// MARK: - Settings Row Components
extension SettingsView {
    
    @ViewBuilder
    private var playbackSpeedRow: some View {
        RowItem(
            icon: playbackSpeedIcon,
            label: "Playback Speed",
            tint: Color.accentColor,
            framedIcon: true) {
                playbackSpeedControl
            }
    }
    
    @ViewBuilder
    private var playbackSpeedControl: some View {
        if userManager.hasPremiumAccess {
            playbackSpeedMenu
        } else {
            playbackSpeedLocked
        }
    }
    
    @ViewBuilder
    private var playbackSpeedMenu: some View {
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
                Text(currentSpeed == 1.0 ? "Normal" : "\(currentSpeed, specifier: "%.1fx")")
                    .foregroundStyle(Color.accentColor)
                    .textBody()
                
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Color.accentColor)
                    .textDetail()
            }
        }
        .onReceive(player.$playbackSpeed) { newSpeed in
            currentSpeed = newSpeed
        }
    }
    
    @ViewBuilder
    private var playbackSpeedLocked: some View {
        HStack {
            Text("\(currentSpeed, specifier: "%.1fx")")
                .foregroundStyle(Color.accentColor)
                .textBody()
            
            Image(systemName: "chevron.up.chevron.down")
                .foregroundStyle(Color.accentColor)
                .textDetail()
        }
        .onTapGesture {
            activeSheet = .upgrade
        }
    }
    
    @ViewBuilder
    private var skipBackwardRow: some View {
        RowItem(
            icon: backwardIntervalIcon,
            label: "Skip Backwards",
            tint: Color.blue,
            framedIcon: true) {
                skipBackwardControl
            }
    }
    
    @ViewBuilder
    private var skipBackwardControl: some View {
        if userManager.hasPremiumAccess {
            skipBackwardMenu
        } else {
            skipBackwardLocked
        }
    }
    
    @ViewBuilder
    private var skipBackwardMenu: some View {
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
                    .foregroundStyle(Color.accentColor)
                    .textBody()
                
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Color.accentColor)
                    .textDetail()
            }
        }
        .onReceive(player.$backwardInterval) { newBackwardInterval in
            currentBackwardInterval = newBackwardInterval
        }
    }
    
    @ViewBuilder
    private var skipBackwardLocked: some View {
        HStack {
            Text("\(currentBackwardInterval, specifier: "%.0fs")")
                .foregroundStyle(Color.accentColor)
                .textBody()
            
            Image(systemName: "chevron.up.chevron.down")
                .foregroundStyle(Color.accentColor)
                .textDetail()
        }
        .onTapGesture {
            activeSheet = .upgrade
        }
    }
    
    @ViewBuilder
    private var skipForwardRow: some View {
        RowItem(
            icon: forwardIntervalIcon,
            label: "Skip Forwards",
            tint: Color.blue,
            framedIcon: true) {
                skipForwardControl
            }
    }
    
    @ViewBuilder
    private var skipForwardControl: some View {
        if userManager.hasPremiumAccess {
            skipForwardMenu
        } else {
            skipForwardLocked
        }
    }
    
    @ViewBuilder
    private var skipForwardMenu: some View {
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
                    .foregroundStyle(Color.accentColor)
                    .textBody()
                
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Color.accentColor)
                    .textDetail()
            }
        }
        .onReceive(player.$forwardInterval) { newForwardInterval in
            currentForwardInterval = newForwardInterval
        }
    }
    
    @ViewBuilder
    private var skipForwardLocked: some View {
        HStack {
            Text("\(currentForwardInterval, specifier: "%.0fs")")
                .foregroundStyle(Color.accentColor)
                .textBody()
            
            Image(systemName: "chevron.up.chevron.down")
                .foregroundStyle(Color.accentColor)
                .textDetail()
        }
        .onTapGesture {
            activeSheet = .upgrade
        }
    }
    
    @ViewBuilder
    private var autoplayRow: some View {
        RowItem(
            icon: "checkmark.arrow.trianglehead.clockwise",
            label: "Autoplay Next Episode",
            tint: Color.orange,
            framedIcon: true,
            showDivider: false) {
                autoplayControl
            }
    }

    @ViewBuilder
    private var autoplayControl: some View {
        if userManager.hasPremiumAccess {
            Toggle(isOn: $player.autoplayNext) {
                Text("Autoplay Next Episode")
            }
            .tint(.accentColor)
            .labelsHidden()
            .symbolRenderingMode(.hierarchical)
        } else {
            HStack {
                Text("Off")
                    .textBody()
                
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Color.accentColor)
            }
            .onTapGesture {
                activeSheet = .upgrade
            }
        }
    }
    
    @ViewBuilder
    private var notificationsRow: some View {
        RowItem(
            icon: "bell",
            label: "Notifications",
            tint: Color.red,
            framedIcon: true,
            showDivider: false) {
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
}

// MARK: - Computed Properties
extension SettingsView {
    
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
}

// MARK: - Methods
extension SettingsView {
    
    private func loadStatistics() async {
        let context = PersistenceController.shared.container.viewContext
        
        do {
            let newStats = try await AppStatistics.load(from: context)
            
            try? await Task.sleep(for: .nanoseconds(1))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut) {
                    statistics = newStats
                }
            }
        } catch {
            print("Error loading statistics: \(error)")
        }
    }
    
    private func handleNotificationToggle(_ enabled: Bool) {
        if enabled {
            if systemNotificationsGranted {
                appNotificationsEnabled = true
            } else if notificationAuthStatus == .notDetermined {
                showNotificationRequest = true
            } else {
                showNotificationAlert = true
            }
        } else {
            appNotificationsEnabled = false
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let wasGranted = systemNotificationsGranted
                systemNotificationsGranted = (settings.authorizationStatus == .authorized)
                notificationAuthStatus = settings.authorizationStatus
                
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
